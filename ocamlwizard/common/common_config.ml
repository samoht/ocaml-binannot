(**************************************************************************)
(*                                                                        *)
(*  Ocamlwizard                                                           *)
(*  David Baudet and Mohamed Iguernelala                                  *)
(*  Copyright 2008 INRIA Saclay - Ile-de-France                           *)
(*                                                                        *)
(*  This software is free software; you can redistribute it and/or        *)
(*  modify it under the terms of the GNU Library General Public           *)
(*  License version 2.1, with the special exception on linking            *)
(*  described in file LICENSE.                                            *)
(*                                                                        *)
(*  This software is distributed in the hope that it will be useful,      *)
(*  but WITHOUT ANY WARRANTY; without even the implied warranty of        *)
(*  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.                  *)
(*                                                                        *)
(**************************************************************************)

open Arg
open Interface

let match_annot = ref false
let match_depth = ref 1

let debug = ref false

let ocaml_compiler = "ocamlc -c -dtypes"
let printer = ref Default_printer
let _parser = ref Default_parser
let kind    = ref ""

(** parse the incompleted file and stop *)
let parse_only = ref false

(** parse the incompleted file, compile the generated file and stop *)
let compile_only = ref false
  
(** To return code 17 on autogenerated test with a Dot as final character *)
let dot_test = ref false

let include_dirs = ref ([]: string list)

let fic_source = ref "" 
let pos = ref ""
let posi = ref 0
let absolute_filenames = ref true
let qualid = ref (Longident.Lident "")
let loc = ref (-1, -1)
let expand_loc = ref (-1, -1)
let root_dir = ref ""


let set_file f =
  if not (Sys.file_exists f) then raise (Arg.Bad (f ^ ": no such file"));
(*
  let f = 
    if Filename.is_relative f then Filename.concat (Sys.getcwd ()) f else f 
  in
*)
  fic_source := f

let get_loc s cmd =
  try
    Scanf.sscanf s "%d-%d" (fun i j -> i,j)
  with Scanf.Scan_failure _ | End_of_file ->
    raise (Arg.Bad (cmd ^ ": illegal location specification"))
      
let set_expand arg = expand_loc := get_loc arg "Completion"

let set_match_depth depth = 
  try
    let n = int_of_string depth
    in if n <= 0 then raise Exit;
    match_depth := n
  with
      Exit -> 
	raise (Arg.Bad ("Completion : invalid match-depth value"))
    | _ ->
	raise (Arg.Bad ("Completion : illegal match-depth specification"))
	  
let set_qualid flat_id = qualid := Longident.parse flat_id


let add_include_dirs arg = 
  include_dirs := (!include_dirs)@[arg]

let search_dirs () = "./" :: (!include_dirs @ [Config.standard_library])
  
let i_dirs () = 
  add_include_dirs Config.standard_library;
  !include_dirs
  
let set_printer = function
  | "ocaml-pp" -> printer := Ocaml_printer
  | _  -> raise (Arg.Bad ("-printer : invalid argument"))
	

let set_parser = function
  |  "default-parser"         -> _parser := Default_parser
  | _  -> raise (Arg.Bad ("-parser : invalid argument"))
	

type refactor_option = 
    | Rename 
    | Depend
    | Qualif

type command = 
    | Nothing 
    | Completion 
    | Compile 
    | Locate 
    | Refactor of refactor_option


let get_refactor_option = function
  | "-rename" -> Refactor Rename
  | "-depend" -> Refactor Depend
  | "-qualif" -> Refactor Qualif
  | _         -> raise (Arg.Bad " refactor : wrong option")


let command = ref Completion

let compile_index = ref 0



let options = 
  [  
    ("-pos",Set_string pos, 
     ": set the position of completion");
    
    ("-I", String add_include_dirs,  
     ": directories to include for the completion");
    
    ("-expand",String set_expand,
     ": the pattern to expand when expanding a pattern variable");
    
    ("-match-annot",Set match_annot,
     ": don't typecheck for match completion (to show limitations)");
    
    ("-match-depth",String set_match_depth,
     ": depth of patterns when completing a pattern matching");
    
    ("-printer",String set_printer,
     ": choose the output format. ");
   
    ("-parser",String set_parser,
     ": choose the used parser for error recovery");

    ("-debug",Set debug , 
     ": used to desplay debug messages on erreur formatter");

    ("-relative-filename", Clear absolute_filenames, 
     ": do not enforce absolute filenames");
    
    ("-root-dir", Set_string root_dir, 
     ": <dir>  sets the root directory for command `locate'");
    
    ("-parse-only",Set parse_only , 
     ": completion command, only parse the file (for tests)");
    
    ("-compile-only",Set compile_only , 
     ": completion command, only parse and compile the file (for tests)");
    
    ("-dot-test",Set dot_test , 
     ": completion command, for automated tests")
  ]

let usage =" usage : ocamlwizard [common options] [command] [command's options]"
let usage = usage ^ "\n" ^ " (Please refer to the user manual for more details.)"
let usage = usage ^ "\n"

exception Exit_typing

let anonymous = function
  | "compile" -> 
      compile_index := !Arg.current;
      command := Compile;
      Arg.current := Array.length Sys.argv

  | "refactor" -> failwith "not yet"
(*
      let i = !Arg.current in 
      if i > Array.length Sys.argv - 6 then 
	raise (Arg.Bad "refactor: too few arguments");

      command := get_refactor_option  Sys.argv.(i + 1) ;
      Refactor_env.set_loc_id (get_loc Sys.argv.(i + 2) "refactor") ;
      begin
	match !command with  
 
	  | Refactor Rename ->
	      if i > Array.length Sys.argv - 7 then 
		raise (Arg.Bad "refactor: too few arguments");
	      Refactor_env.set_old_id  (Sys.argv.(i + 3));
	      Refactor_env.set_new_id  (Sys.argv.(i + 4));
	      Refactor_env.set_file  (Sys.argv.(i + 5));
	      compile_index := i + 5;
	      Arg.current := Array.length Sys.argv;
	      
	  | Refactor Depend ->
	      Refactor_env.set_old_id  (Sys.argv.(i + 3));
	      Refactor_env.set_file  (Sys.argv.(i + 4));
	      compile_index := i + 4;
	      Arg.current := Array.length Sys.argv
 		
	  | Refactor Qualif ->  
	      command := Refactor Rename;
	      Refactor_env.set_old_id  (Sys.argv.(i + 3));
	      Refactor_env.set_new_id  (Sys.argv.(i + 3));
	      Refactor_env.set_file  (Sys.argv.(i + 4));
	      compile_index := i + 4;
	      Arg.current := Array.length Sys.argv
 		
	  | Locate | Compile | Completion | Nothing  -> 
	      Debug.unreachable "Common_config" 10
	    

      end;
*)
	
  | "locate" -> 
      let i = !Arg.current in 
      if i > Array.length Sys.argv - 4 then 
	raise (Arg.Bad "locate: too few arguments");
      set_qualid Sys.argv.(i + 1);
      loc := get_loc Sys.argv.(i + 2) "locate";
      set_file Sys.argv.(i + 3);
      Arg.current := i + 3;
      command := Locate;
     	
  | "completion" ->
      command := Completion

  | f when Sys.file_exists f -> fic_source := f
  | s -> raise (Arg.Bad ("don't know what to do with " ^ s))

let rcfile = ".ocamlwizard"

let () = 
  if Sys.file_exists rcfile then begin
    try
      let buf = Buffer.create 1024 in
      let c = open_in rcfile in
      begin
	try while true do Buffer.add_char buf (input_char c) done
	with End_of_file -> close_in c
      end;
      let r = Str.regexp "[ \n]+" in
      let args = 
	Array.of_list (Sys.argv.(0) :: Str.split r (Buffer.contents buf)) 
      in
      Arg.parse_argv ~current:(ref 0) args options anonymous usage 
    with e ->
      Format.eprintf "warning: could not load .ocamlwizard (%s)@."
	(Printexc.to_string e)
  end
