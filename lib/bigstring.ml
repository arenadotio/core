INCLUDE "core_config.mlh"

open Core_kernel.Std
open Unix
open Bigarray
open Sexplib.Std

include Core_kernel.Std.Bigstring

exception IOError of int * exn with sexp

external init : unit -> unit = "bigstring_init_stub"

let () =
  Callback.register_exception "Bigstring.End_of_file" End_of_file;
  Callback.register_exception "Bigstring.IOError" (IOError (0, Exit));
  init ()

external aux_create: max_mem_waiting_gc:int -> size:int -> t = "bigstring_alloc"

let create ?max_mem_waiting_gc size =
  let max_mem_waiting_gc =
    match max_mem_waiting_gc with
    | None -> ~-1
    | Some v -> Float.to_int (Byte_units.bytes v)
  in
  (* vgatien-baron: aux_create ~size:(-1) throws Out of memory, which could be quite
     confusing during debugging. *)
  if size < 0 then invalid_argf "create: size = %d < 0" size ();
  aux_create ~max_mem_waiting_gc ~size

TEST "create with different max_mem_waiting_gc" =
  Gc.full_major ();
  let count_gc_cycles mem_units =
    let cycles = ref 0 in
    let alarm = Gc.create_alarm (fun () -> incr cycles) in
    let large_int = 10_000 in
    let max_mem_waiting_gc = Byte_units.create mem_units 256. in
    for _i = 0 to large_int do
      let (_ : t) = create ~max_mem_waiting_gc large_int in
      ()
    done;
    Gc.delete_alarm alarm;
    !cycles
  in
  let large_max_mem = count_gc_cycles `Megabytes in
  let small_max_mem = count_gc_cycles `Bytes in
  (* We don't care if it's twice as many, we are only testing that there are less cycles
  involved *)
  (2 * large_max_mem) < small_max_mem


external length : t -> int = "bigstring_length" "noalloc"

external is_mmapped : t -> bool = "bigstring_is_mmapped_stub" "noalloc"

let init n ~f =
  let t = create n in
  for i = 0 to n - 1; do
    t.{i} <- f i;
  done;
  t
;;

let check_args ~loc ~pos ~len (bstr : t) =
  if pos < 0 then invalid_arg (loc ^ ": pos < 0");
  if len < 0 then invalid_arg (loc ^ ": len < 0");
  let bstr_len = length bstr in
  if bstr_len < pos + len then
    invalid_arg (sprintf "Bigstring.%s: length(bstr) < pos + len" loc)

let get_opt_len bstr ~pos = function
  | Some len -> len
  | None -> length bstr - pos

let check_min_len ~loc ~len = function
  | None -> 0
  | Some min_len ->
      if min_len > len then (
        let msg = sprintf "%s: min_len (%d) > len (%d)" loc min_len len in
        invalid_arg msg);
      if min_len < 0 then (
        let msg = sprintf "%s: min_len (%d) < 0" loc min_len in
        invalid_arg msg);
      min_len

let sub_shared ?(pos = 0) ?len (bstr : t) =
  let len = get_opt_len bstr ~pos len in
  Array1.sub bstr pos len

(* Input functions *)

external unsafe_read :
  min_len : int -> file_descr -> pos : int -> len : int -> t -> int
  = "bigstring_read_stub"

let read ?min_len fd ?(pos = 0) ?len bstr =
  let len = get_opt_len bstr ~pos len in
  let loc = "read" in
  check_args ~loc ~pos ~len bstr;
  let min_len = check_min_len ~loc ~len min_len in
  unsafe_read ~min_len fd ~pos ~len bstr

external unsafe_pread_assume_fd_is_nonblocking_stub :
  file_descr -> offset : int -> pos : int -> len : int -> t -> int
  = "bigstring_pread_assume_fd_is_nonblocking_stub"

let pread_assume_fd_is_nonblocking fd ~offset ?(pos = 0) ?len bstr =
  let len = get_opt_len bstr ~pos len in
  let loc = "pread" in
  check_args ~loc ~pos ~len bstr;
  unsafe_pread_assume_fd_is_nonblocking_stub fd ~offset ~pos ~len bstr

let really_read fd ?(pos = 0) ?len bstr =
  let len = get_opt_len bstr ~pos len in
  ignore (read ~min_len:len fd ~pos ~len bstr)

external unsafe_really_recv :
  file_descr -> pos : int -> len : int -> t -> unit
  = "bigstring_really_recv_stub"

let really_recv sock ?(pos = 0) ?len bstr =
  let len = get_opt_len bstr ~pos len in
  check_args ~loc:"really_recv" ~pos ~len bstr;
  unsafe_really_recv sock ~pos ~len bstr

external unsafe_recvfrom_assume_fd_is_nonblocking :
  file_descr -> pos : int -> len : int -> t -> int * sockaddr
  = "bigstring_recvfrom_assume_fd_is_nonblocking_stub"

let recvfrom_assume_fd_is_nonblocking sock ?(pos = 0) ?len bstr =
  let len = get_opt_len bstr ~pos len in
  check_args ~loc:"recvfrom_assume_fd_is_nonblocking" ~pos ~len bstr;
  unsafe_recvfrom_assume_fd_is_nonblocking sock ~pos ~len bstr

external unsafe_read_assume_fd_is_nonblocking :
  file_descr -> pos : int -> len : int -> t -> int
  = "bigstring_read_assume_fd_is_nonblocking_stub"

let read_assume_fd_is_nonblocking fd ?(pos = 0) ?len bstr =
  let len = get_opt_len bstr ~pos len in
  check_args ~loc:"read_assume_fd_is_nonblocking" ~pos ~len bstr;
  unsafe_read_assume_fd_is_nonblocking fd ~pos ~len bstr

external unsafe_input :
  min_len : int -> in_channel -> pos : int -> len : int -> t -> int
  = "bigstring_input_stub"

let input ?min_len ic ?(pos = 0) ?len bstr =
  let len = get_opt_len bstr ~pos len in
  let loc = "input" in
  check_args ~loc ~pos ~len bstr;
  let min_len = check_min_len ~loc ~len min_len in
  unsafe_input ~min_len ic ~pos ~len bstr

let really_input ic ?(pos = 0) ?len bstr =
  let len = get_opt_len bstr ~pos len in
  check_args ~loc:"really_input" ~pos ~len bstr;
  ignore (unsafe_input ~min_len:len ic ~pos ~len bstr)

(* Output functions *)

external unsafe_really_write :
  file_descr -> pos : int -> len : int -> t -> unit
  = "bigstring_really_write_stub"

let really_write fd ?(pos = 0) ?len bstr =
  let len = get_opt_len bstr ~pos len in
  check_args ~loc:"really_write" ~pos ~len bstr;
  unsafe_really_write fd ~pos ~len bstr

external unsafe_pwrite_assume_fd_is_nonblocking :
  file_descr -> offset : int -> pos : int -> len : int -> t -> int
  = "bigstring_pwrite_assume_fd_is_nonblocking_stub"

let pwrite_assume_fd_is_nonblocking fd ~offset ?(pos = 0) ?len bstr =
  let len = get_opt_len bstr ~pos len in
  let loc = "pwrite" in
  check_args ~loc ~pos ~len bstr;
  unsafe_pwrite_assume_fd_is_nonblocking fd ~offset ~pos ~len bstr

IFDEF MSG_NOSIGNAL THEN
external unsafe_really_send_no_sigpipe :
  file_descr -> pos : int -> len : int -> t -> unit
  = "bigstring_really_send_no_sigpipe_stub"

let really_send_no_sigpipe fd ?(pos = 0) ?len bstr =
  let len = get_opt_len bstr ~pos len in
  check_args ~loc:"really_send_no_sigpipe" ~pos ~len bstr;
  unsafe_really_send_no_sigpipe fd ~pos ~len bstr

external unsafe_send_nonblocking_no_sigpipe :
  file_descr -> pos : int -> len : int -> t -> int
  = "bigstring_send_nonblocking_no_sigpipe_stub"

let unsafe_send_nonblocking_no_sigpipe fd ~pos ~len buf =
  let res = unsafe_send_nonblocking_no_sigpipe fd ~pos ~len buf in
  if res = -1 then None
  else Some res

let send_nonblocking_no_sigpipe fd ?(pos = 0) ?len bstr =
  let len = get_opt_len bstr ~pos len in
  check_args ~loc:"send_nonblocking_no_sigpipe" ~pos ~len bstr;
  unsafe_send_nonblocking_no_sigpipe fd ~pos ~len bstr

external unsafe_sendto_nonblocking_no_sigpipe :
  file_descr -> pos : int -> len : int -> t -> sockaddr -> int
  = "bigstring_sendto_nonblocking_no_sigpipe_stub"

let unsafe_sendto_nonblocking_no_sigpipe fd ~pos ~len buf sockaddr =
  let res = unsafe_sendto_nonblocking_no_sigpipe fd ~pos ~len buf sockaddr in
  if res = -1 then None
  else Some res

let sendto_nonblocking_no_sigpipe fd ?(pos = 0) ?len bstr sockaddr =
  let len = get_opt_len bstr ~pos len in
  check_args ~loc:"sendto_nonblocking_no_sigpipe" ~pos ~len bstr;
  unsafe_sendto_nonblocking_no_sigpipe fd ~pos ~len bstr sockaddr

let really_send_no_sigpipe                = Ok really_send_no_sigpipe
let send_nonblocking_no_sigpipe           = Ok send_nonblocking_no_sigpipe
let sendto_nonblocking_no_sigpipe         = Ok sendto_nonblocking_no_sigpipe
let unsafe_really_send_no_sigpipe         = Ok unsafe_really_send_no_sigpipe
let unsafe_send_nonblocking_no_sigpipe    = Ok unsafe_send_nonblocking_no_sigpipe

ELSE

let really_send_no_sigpipe             = unimplemented "Bigstring.really_send_no_sigpipe"
let send_nonblocking_no_sigpipe        = unimplemented "Bigstring.send_nonblocking_no_sigpipe"
let sendto_nonblocking_no_sigpipe      = unimplemented "Bigstring.sendto_nonblocking_no_sigpipe"
let unsafe_really_send_no_sigpipe      = unimplemented "Bigstring.unsafe_really_send_no_sigpipe"
let unsafe_send_nonblocking_no_sigpipe = unimplemented "Bigstring.unsafe_send_nonblocking_no_sigpipe"

ENDIF

external unsafe_write :
  file_descr -> pos : int -> len : int -> t -> int = "bigstring_write_stub"

let write fd ?(pos = 0) ?len bstr =
  let len = get_opt_len bstr ~pos len in
  check_args ~loc:"write" ~pos ~len bstr;
  unsafe_write fd ~pos ~len bstr

external unsafe_write_assume_fd_is_nonblocking :
  file_descr -> pos : int -> len : int -> t -> int
  = "bigstring_write_assume_fd_is_nonblocking_stub"

let write_assume_fd_is_nonblocking fd ?(pos = 0) ?len bstr =
  let len = get_opt_len bstr ~pos len in
  check_args ~loc:"write_assume_fd_is_nonblocking" ~pos ~len bstr;
  unsafe_write_assume_fd_is_nonblocking fd ~pos ~len bstr

external unsafe_writev :
  file_descr -> t Core_unix.IOVec.t array -> int -> int
  = "bigstring_writev_stub"

let get_iovec_count loc iovecs = function
  | None -> Array.length iovecs
  | Some count ->
      if count < 0 then invalid_arg (loc ^ ": count < 0");
      let n_iovecs = Array.length iovecs in
      if count > n_iovecs then invalid_arg (loc ^ ": count > n_iovecs");
      count

let writev fd ?count iovecs =
  let count = get_iovec_count "writev" iovecs count in
  unsafe_writev fd iovecs count

external unsafe_writev_assume_fd_is_nonblocking :
  file_descr -> t Core_unix.IOVec.t array -> int -> int
  = "bigstring_writev_assume_fd_is_nonblocking_stub"

let writev_assume_fd_is_nonblocking fd ?count iovecs =
  let count = get_iovec_count "writev_nonblocking" iovecs count in
  unsafe_writev_assume_fd_is_nonblocking fd iovecs count
;;

external unsafe_output :
  min_len : int -> out_channel -> pos : int -> len : int -> t -> int
  = "bigstring_output_stub"

let output ?min_len oc ?(pos = 0) ?len bstr =
  let len = get_opt_len bstr ~pos len in
  let loc = "output" in
  check_args ~loc ~pos ~len bstr;
  let min_len = check_min_len ~loc ~len min_len in
  unsafe_output oc ~min_len ~pos ~len bstr

let really_output oc ?(pos = 0) ?len bstr =
  let len = get_opt_len bstr ~pos len in
  check_args ~loc:"really_output" ~pos ~len bstr;
  ignore (unsafe_output oc ~min_len:len ~pos ~len bstr)

IFDEF RECVMMSG THEN

external unsafe_recvmmsg_assume_fd_is_nonblocking :
  file_descr
  -> t Core_unix.IOVec.t array
  -> int
  -> sockaddr array option
  -> int array
  -> int
  = "bigstring_recvmmsg_assume_fd_is_nonblocking_stub"

let recvmmsg_assume_fd_is_nonblocking fd ?count ?srcs iovecs ~lens =
  let loc = "recvmmsg_assume_fd_is_nonblocking" in
  let count = get_iovec_count loc iovecs count in
  begin match srcs with
  | None -> ()
  | Some a -> if count > Array.length a then invalid_arg (loc ^ ": count > n_srcs")
  end;
  if count > Array.length lens then invalid_arg (loc ^ ": count > n_lens");
  unsafe_recvmmsg_assume_fd_is_nonblocking fd iovecs count srcs lens
;;

TEST_MODULE "recvmmsg smoke" = struct
  module IOVec = Core_unix.IOVec
  module Inet_addr = Core_unix.Inet_addr

  let count = 10
  let fd = socket PF_INET SOCK_DGRAM 0
  let () = bind fd (ADDR_INET (Inet_addr.bind_any, 0))
  let iovecs = Array.init count ~f:(fun _ -> IOVec.of_bigstring (create 1500))
  let srcs = Array.create ~len:count (ADDR_INET (Inet_addr.bind_any, 0))
  let lens = Array.create ~len:count 0
  let short_srcs = Array.create ~len:(count - 1) (ADDR_INET (Inet_addr.bind_any, 0))
  let () = set_nonblock fd

  TEST =
    try recvmmsg_assume_fd_is_nonblocking fd iovecs ~count ~srcs ~lens = 0
    with Unix_error _ -> true | _ -> false
  TEST =
    try recvmmsg_assume_fd_is_nonblocking fd iovecs ~lens = 0
    with Unix_error _ -> true | _ -> false
  TEST =
    try recvmmsg_assume_fd_is_nonblocking fd iovecs ~count:(count / 2) ~srcs ~lens = 0
    with Unix_error _ -> true | _ -> false
  TEST =
    try recvmmsg_assume_fd_is_nonblocking fd iovecs ~count:0 ~srcs ~lens = 0
    with Unix_error _ -> true | _ -> false
  TEST =
    try
      ignore (recvmmsg_assume_fd_is_nonblocking fd iovecs ~count:(count + 1) ~lens);
      false
    with Unix_error _ -> false | _ -> true
  TEST =
    try
      ignore (recvmmsg_assume_fd_is_nonblocking fd iovecs ~srcs:short_srcs ~lens);
      false
    with Unix_error _ -> false | _ -> true
end
;;

let recvmmsg_assume_fd_is_nonblocking =
  Ok recvmmsg_assume_fd_is_nonblocking
;;

ELSE                                    (* NDEF RECVMMSG *)

let recvmmsg_assume_fd_is_nonblocking =
  unimplemented "Bigstring.recvmmsg_assume_fd_is_nonblocking"
;;

ENDIF                                   (* RECVMMSG *)

(* Memory mapping *)

IFDEF MSG_NOSIGNAL THEN
(* Input and output, linux only *)

external unsafe_sendmsg_nonblocking_no_sigpipe :
  file_descr -> t Core_unix.IOVec.t array -> int -> int
  = "bigstring_sendmsg_nonblocking_no_sigpipe_stub"

let unsafe_sendmsg_nonblocking_no_sigpipe fd iovecs count =
  let res = unsafe_sendmsg_nonblocking_no_sigpipe fd iovecs count in
  if res = -1 then None
  else Some res

let sendmsg_nonblocking_no_sigpipe fd ?count iovecs =
  let count = get_iovec_count "sendmsg_nonblocking_no_sigpipe" iovecs count in
  unsafe_sendmsg_nonblocking_no_sigpipe fd iovecs count

let sendmsg_nonblocking_no_sigpipe        = Ok sendmsg_nonblocking_no_sigpipe
let unsafe_sendmsg_nonblocking_no_sigpipe = Ok unsafe_sendmsg_nonblocking_no_sigpipe

ELSE

let sendmsg_nonblocking_no_sigpipe =
  unimplemented "Bigstring.sendmsg_nonblocking_no_sigpipe"
;;

let unsafe_sendmsg_nonblocking_no_sigpipe =
  unimplemented "Bigstring.unsafe_sendmsg_nonblocking_no_sigpipe"
;;

ENDIF
