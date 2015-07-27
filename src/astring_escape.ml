(*---------------------------------------------------------------------------
   Copyright (c) 2015 Daniel C. Bünzli. All rights reserved.
   Distributed under the BSD3 license, see license at the end of the file.
   %%NAME%% release %%VERSION%%
  ---------------------------------------------------------------------------*)

open Astring_unsafe

let hex_digit =
  [|'0';'1';'2';'3';'4';'5';'6';'7';'8';'9';'A';'B';'C';'D';'E';'F'|]

let hex_escape b k c =
  let byte = char_to_byte c in
  let hi = byte / 16 in
  let lo = byte mod 16 in
  bytes_unsafe_set b (k    ) '\\';
  bytes_unsafe_set b (k + 1) 'x';
  bytes_unsafe_set b (k + 2) (array_unsafe_get hex_digit hi);
  bytes_unsafe_set b (k + 3) (array_unsafe_get hex_digit lo);
  ()

let letter_escape b k letter =
  bytes_unsafe_set b (k    ) '\\';
  bytes_unsafe_set b (k + 1) letter;
  ()

(* Character escapes *)

let char_escape = function
| '\\' -> "\\\\"
| '\x20' .. '\x7E' as c ->
    let b = Bytes.create 1 in
    bytes_unsafe_set b 0 c;
    bytes_unsafe_to_string b
| c (* hex escape *) ->
    let b = Bytes.create 4 in
    hex_escape b 0 c;
    bytes_unsafe_to_string b

let char_escape_char = function
| '\\' -> "\\\\"
| '\'' -> "\\'"
| '\b' -> "\\b"
| '\t' -> "\\t"
| '\n' -> "\\n"
| '\r' -> "\\r"
| '\x20' .. '\x7E' as c ->
    let b = Bytes.create 1 in
    bytes_unsafe_set b 0 c;
    bytes_unsafe_to_string b
| c (* hex escape *) ->
    let b = Bytes.create 4 in
    hex_escape b 0 c;
    bytes_unsafe_to_string b

(* String escapes *)

let escape s =
  let max_idx = string_length s - 1 in
  let rec escaped_len i l =
    if i > max_idx then l else
    match string_unsafe_get s i with
    | '\\'               -> escaped_len (i + 1) (l + 2)
    | '\x20' .. '\x7E'   -> escaped_len (i + 1) (l + 1)
    | _ (* hex escape *) -> escaped_len (i + 1) (l + 4)
  in
  let escaped_len = escaped_len 0 0 in
  if escaped_len = string_length s then s else
  let b = Bytes.create escaped_len in
  let rec loop i k =
    if i > max_idx then bytes_unsafe_to_string b else
    match string_unsafe_get s i with
    | '\\' ->
        letter_escape b k '\\'; loop (i + 1) (k + 2)
    | '\x20' .. '\x7E' as c ->
        bytes_unsafe_set b k c; loop (i + 1) (k + 1)
    | c ->
        hex_escape b k c; loop (i + 1) (k + 4)
  in
  loop 0 0

let escape_string s =
  let max_idx = string_length s - 1 in
  let rec escaped_len i l =
    if i > max_idx then l else
    match string_unsafe_get s i with
    | '\b' | '\t' | '\n' | '\r' | '\"' | '\\' ->
        escaped_len (i + 1) (l + 2)
    | '\x20' .. '\x7E'   ->
        escaped_len (i + 1) (l + 1)
    | _ (* hex escape *) ->
        escaped_len (i + 1) (l + 4)
  in
  let escaped_len = escaped_len 0 0 in
  if escaped_len = string_length s then s else
  let b = Bytes.create escaped_len in
  let rec loop i k =
    if i > max_idx then bytes_unsafe_to_string b else
    match string_unsafe_get s i with
    | '\b' -> letter_escape b k 'b'; loop (i + 1) (k + 2)
    | '\t' -> letter_escape b k 't'; loop (i + 1) (k + 2)
    | '\n' -> letter_escape b k 'n'; loop (i + 1) (k + 2)
    | '\r' -> letter_escape b k 'r'; loop (i + 1) (k + 2)
    | '\"' -> letter_escape b k '"'; loop (i + 1) (k + 2)
    | '\\' -> letter_escape b k '\\'; loop (i + 1) (k + 2)
    | '\x20' .. '\x7E' as c ->
        bytes_unsafe_set b k c; loop (i + 1) (k + 1)
    | c ->
        hex_escape b k c; loop (i + 1) (k + 4)
  in
  loop 0 0

(* Unescaping *)

let is_hex_digit = function
| '0' .. '9' | 'A' .. 'F' | 'a' .. 'f' -> true
| _ -> false

let hex_value = function
| '0' .. '9' as c -> char_to_byte c - 0x30
| 'A' .. 'F' as c -> 10 + (char_to_byte c - 0x41)
| 'a' .. 'f' as c -> 10 + (char_to_byte c - 0x61)
| _ -> assert false

let unescaped_len ~ocaml s =    (* derives length and checks syntax validity *)
  let max_idx = string_length s - 1 in
  let rec loop i l =
    if i > max_idx then Some l else
    if string_unsafe_get s i <> '\\' then loop (i + 1) (l + 1) else
    let i = i + 1 in
    if i > max_idx then None (* truncated escape *) else
    match string_unsafe_get s i with
    | '\\' -> loop (i + 1) (l + 1)
    | 'x' ->
        let i = i + 2 in
        if i > max_idx then None (* truncated escape *) else
        if not (is_hex_digit (string_unsafe_get s (i - 1)) &&
                is_hex_digit (string_unsafe_get s (i    )))
        then None (* invalid escape *)
        else loop (i + 1) (l + 1)
    | ('b' | 't' | 'n' | 'r' | '"' | '\'') when ocaml -> loop (i + 1) (l + 1)
    | c -> None (* invalid escape *)
  in
  loop 0 0

let _unescape ~ocaml s = match unescaped_len ~ocaml s with
| None -> None
| Some l when l = string_length s -> Some s
| Some l ->
    let b = Bytes.create l in
    let max_idx = string_length s - 1 in
    let rec loop i k =
      if i > max_idx then Some (bytes_unsafe_to_string b) else
      let c = string_unsafe_get s i in
      if c <> '\\' then (bytes_unsafe_set b k c; loop (i + 1) (k + 1)) else
      let i = i + 1 (* validity checked by unescaped_len *) in
      match string_unsafe_get s i with
      | '\\' -> bytes_unsafe_set b k '\\'; loop (i + 1) (k + 1)
      | 'x' ->
          let i = i + 2 (* validity checked by unescaped_len *) in
          let hi = hex_value @@ string_unsafe_get s (i - 1) in
          let lo = hex_value @@ string_unsafe_get s (i    ) in
          let c = char_unsafe_of_byte @@ (hi lsl 4) + lo in
          bytes_unsafe_set b k c; loop (i + 1) (k + 1)
      (* The following cases are never reached for ~ocaml:false *)
      | 'b' -> bytes_unsafe_set b k '\b'; loop (i + 1) (k + 1)
      | 't' -> bytes_unsafe_set b k '\t'; loop (i + 1) (k + 1)
      | 'n' -> bytes_unsafe_set b k '\n'; loop (i + 1) (k + 1)
      | 'r' -> bytes_unsafe_set b k '\r'; loop (i + 1) (k + 1)
      | '"' -> bytes_unsafe_set b k '\"'; loop (i + 1) (k + 1)
      | '\'' -> bytes_unsafe_set b k '\''; loop (i + 1) (k + 1)
      | c -> assert false (* because of unescaped_len  *)
    in
    loop 0 0

let unescape s = _unescape ~ocaml:false s
let unescape_string s = _unescape ~ocaml:true s

(*---------------------------------------------------------------------------
   Copyright (c) 2015 Daniel C. Bünzli.
   All rights reserved.

   Redistribution and use in source and binary forms, with or without
   modification, are permitted provided that the following conditions
   are met:

   1. Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.

   2. Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.

   3. Neither the name of Daniel C. Bünzli nor the names of
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
   A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
   OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
   LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
   DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
   THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
   (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
   OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
  ---------------------------------------------------------------------------*)
