(* Read the CRC of the interfaces of the units *)

let load_path = ref ["."]
let first = ref true

let print_crc unit =
  try
    let crc = Dynlink.crc_interface unit !load_path in
    if !first then first := false else print_string ";\n";
    print_string "  \""; print_string unit; print_string "\", ";
    print_int crc
  with exn ->
    prerr_string "Error while reading the interface for ";
    prerr_endline unit;
    begin match exn with
      Sys_error msg -> prerr_endline msg
    | Dynlink.Error _ -> prerr_endline "Ill formed .cmi file"
    | _ -> raise exn
    end;
    exit 2

let main () =
  print_string "let crc_unit_list = [\n";
  Arg.parse
    ["-I", Arg.String(fun dir -> load_path := !load_path @ [dir])]
    print_crc;
  print_string "\n]\n"

let _ = main(); exit 0

     
