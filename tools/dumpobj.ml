(***********************************************************************)
(*                                                                     *)
(*                           Objective Caml                            *)
(*                                                                     *)
(*            Xavier Leroy, projet Cristal, INRIA Rocquencourt         *)
(*                                                                     *)
(*  Copyright 1996 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under the terms of the Q Public License version 1.0.               *)
(*                                                                     *)
(***********************************************************************)

(* $Id$ *)

(* Disassembler for executable and .cmo object files *)

open Obj
open Printf
open Config
open Asttypes
open Lambda
open Emitcode
open Opcodes
open Instruct
open Opnames

(* Read signed and unsigned integers *)

let inputu ic =
  let b1 = input_byte ic in
  let b2 = input_byte ic in
  let b3 = input_byte ic in
  let b4 = input_byte ic in
  (b4 lsl 24) + (b3 lsl 16) + (b2 lsl 8) + b1

let inputs ic =
  let b1 = input_byte ic in
  let b2 = input_byte ic in
  let b3 = input_byte ic in
  let b4 = input_byte ic in
  let b4' = if b4 >= 128 then b4-256 else b4 in
  (b4' lsl 24) + (b3 lsl 16) + (b2 lsl 8) + b1

(* Global variables *)

type global_table_entry =
    Empty
  | Global of Ident.t
  | Constant of Obj.t

let start = ref 0                              (* Position of beg. of code *)
let reloc = ref ([] : (reloc_info * int) list) (* Relocation table *)
let globals = ref ([||] : global_table_entry array) (* Global map *)
let primitives = ref ([||] : string array)     (* Table of primitives *)
let objfile = ref false                        (* true if dumping a .cmo *)

(* Events (indexed by PC) *)

let event_table = (Hashtbl.create 253 : (int, debug_event) Hashtbl.t)

let relocate_event orig ev =
  ev.ev_pos <- orig + ev.ev_pos;
  match ev.ev_repr with
    Event_parent repr -> repr := ev.ev_pos
  | _                 -> ()

let record_events orig evl =
  List.iter 
    (fun ev ->
      relocate_event orig ev;
      Hashtbl.add event_table ev.ev_pos ev)
    evl

(* Print a structured constant *)

let print_float f =
  if String.contains f '.'
  then printf "%s" f
  else printf "%s." f
;;

let rec print_struct_const = function
    Const_base(Const_int i) ->
      printf "%d" i
  | Const_base(Const_float f) ->
      print_float f
  | Const_base(Const_string s) ->
      printf "%S" s
  | Const_base(Const_char c) ->
      printf "%C" c
  | Const_pointer n ->
      printf "%da" n
  | Const_block(tag, args) ->
      printf "<%d>" tag;
      begin match args with
        [] -> ()
      | [a1] ->
          printf "("; print_struct_const a1; printf ")"
      | a1::al ->
          printf "("; print_struct_const a1;
          List.iter (fun a -> printf ", "; print_struct_const a) al;
          printf ")"
      end
  | Const_float_array a ->
      printf "[|";
      List.iter (fun f -> print_float f; printf "; ") a;
      printf "|]"

(* Print an obj *)

let rec print_obj x =
  if Obj.is_block x then begin
    match Obj.tag x with
      252 ->                            (* string *)
        printf "%S" (Obj.magic x : string)
    | 253 ->                            (* float *)
        printf "%.12g" (Obj.magic x : float)
    | 254 ->                            (* float array *)
        let a = (Obj.magic x : float array) in
        printf "[|";
        for i = 0 to Array.length a - 1 do
          if i > 0 then printf ", ";
          printf "%.12g" a.(i)
        done;
        printf "|]"
    | _ ->
        printf "<%d>" (Obj.tag x);
        begin match Obj.size x with
          0 -> ()
        | 1 ->
            printf "("; print_obj (Obj.field x 0); printf ")"
        | n ->
            printf "("; print_obj (Obj.field x 0);
            for i = 1 to n - 1 do
              printf ", "; print_obj (Obj.field x i)
            done;
            printf ")"
        end
  end else
    printf "%d" (Obj.magic x : int)

(* Current position in input file *)

let currpos ic =
  pos_in ic - !start

(* Access in the relocation table *)

let rec rassoc key = function
    [] -> raise Not_found
  | (a,b) :: l -> if b = key then a else rassoc key l

let find_reloc ic =
  rassoc (pos_in ic - !start) !reloc

(* Symbolic printing of global names, etc *)

let print_getglobal_name ic =
  if !objfile then begin
    begin try
      match find_reloc ic with
          Reloc_getglobal id -> print_string (Ident.name id)
        | Reloc_literal sc -> print_struct_const sc
        | _ -> print_string "<wrong reloc>"
    with Not_found ->
      print_string "<no reloc>"
    end;
    ignore (inputu ic);
  end
  else begin
    let n = inputu ic in
    if n >= Array.length !globals || n < 0
    then print_string "<global table overflow>"
    else match !globals.(n) with
           Global id -> print_string(Ident.name id)
         | Constant obj -> print_obj obj
         | _ -> print_string "???"
  end

let print_setglobal_name ic =
  if !objfile then begin
    begin try
      match find_reloc ic with
        Reloc_setglobal id -> print_string (Ident.name id)
      | _ -> print_string "<wrong reloc>"
    with Not_found ->
      print_string "<no reloc>"
    end;
    ignore (inputu ic);
  end
  else begin
    let n = inputu ic in
    if n >= Array.length !globals || n < 0
    then print_string "<global table overflow>"
    else match !globals.(n) with
           Global id -> print_string(Ident.name id)
         | _ -> print_string "???"
  end

let print_primitive ic =
  if !objfile then begin
    begin try
      match find_reloc ic with
        Reloc_primitive s -> print_string s
      | _ -> print_string "<wrong reloc>"
    with Not_found ->
      print_string "<no reloc>"
    end;
    ignore (inputu ic);
  end
  else begin
    let n = inputu ic in
    if n >= Array.length !primitives || n < 0
    then print_int n
    else print_string !primitives.(n)
  end

(* Disassemble one instruction *)

let currpc ic =
  currpos ic / 4

type shape =
  | Nothing
  | Uint
  | Sint
  | Uint_Uint
  | Disp
  | Uint_Disp
  | Sint_Disp
  | Getglobal
  | Getglobal_Uint
  | Setglobal
  | Primitive
  | Uint_Primitive
  | Switch
  | Closurerec
;;

let op_shapes = [
  opACC0, Nothing;
  opACC1, Nothing;
  opACC2, Nothing;
  opACC3, Nothing;
  opACC4, Nothing;
  opACC5, Nothing;
  opACC6, Nothing;
  opACC7, Nothing;
  opACC, Uint;
  opPUSH, Nothing;
  opPUSHACC0, Nothing;
  opPUSHACC1, Nothing;
  opPUSHACC2, Nothing;
  opPUSHACC3, Nothing;
  opPUSHACC4, Nothing;
  opPUSHACC5, Nothing;
  opPUSHACC6, Nothing;
  opPUSHACC7, Nothing;
  opPUSHACC, Uint;
  opPOP, Uint;
  opASSIGN, Uint;
  opENVACC1, Nothing;
  opENVACC2, Nothing;
  opENVACC3, Nothing;
  opENVACC4, Nothing;
  opENVACC, Uint;
  opPUSHENVACC1, Nothing;
  opPUSHENVACC2, Nothing;
  opPUSHENVACC3, Nothing;
  opPUSHENVACC4, Nothing;
  opPUSHENVACC, Uint;
  opPUSH_RETADDR, Disp;
  opAPPLY, Uint;
  opAPPLY1, Nothing;
  opAPPLY2, Nothing;
  opAPPLY3, Nothing;
  opAPPTERM, Uint_Uint;
  opAPPTERM1, Uint;
  opAPPTERM2, Uint;
  opAPPTERM3, Uint;
  opRETURN, Uint;
  opRESTART, Nothing;
  opGRAB, Uint;
  opCLOSURE, Uint_Disp;
  opCLOSUREREC, Closurerec;
  opOFFSETCLOSUREM2, Nothing;
  opOFFSETCLOSURE0, Nothing;
  opOFFSETCLOSURE2, Nothing;
  opOFFSETCLOSURE, Sint;  (* was Uint *)
  opPUSHOFFSETCLOSUREM2, Nothing;
  opPUSHOFFSETCLOSURE0, Nothing;
  opPUSHOFFSETCLOSURE2, Nothing;
  opPUSHOFFSETCLOSURE, Sint; (* was Nothing *)
  opGETGLOBAL, Getglobal;
  opPUSHGETGLOBAL, Getglobal;
  opGETGLOBALFIELD, Getglobal_Uint;
  opPUSHGETGLOBALFIELD, Getglobal_Uint;
  opSETGLOBAL, Setglobal;
  opATOM0, Nothing;
  opATOM, Uint;
  opPUSHATOM0, Nothing;
  opPUSHATOM, Uint;
  opMAKEBLOCK, Uint_Uint;
  opMAKEBLOCK1, Uint;
  opMAKEBLOCK2, Uint;
  opMAKEBLOCK3, Uint;
  opMAKEFLOATBLOCK, Uint;
  opGETFIELD0, Nothing;
  opGETFIELD1, Nothing;
  opGETFIELD2, Nothing;
  opGETFIELD3, Nothing;
  opGETFIELD, Uint;
  opGETFLOATFIELD, Uint;
  opSETFIELD0, Nothing;
  opSETFIELD1, Nothing;
  opSETFIELD2, Nothing;
  opSETFIELD3, Nothing;
  opSETFIELD, Uint;
  opSETFLOATFIELD, Uint;
  opVECTLENGTH, Nothing;
  opGETVECTITEM, Nothing;
  opSETVECTITEM, Nothing;
  opGETSTRINGCHAR, Nothing;
  opSETSTRINGCHAR, Nothing;
  opBRANCH, Disp;
  opBRANCHIF, Disp;
  opBRANCHIFNOT, Disp;
  opSWITCH, Switch;
  opBOOLNOT, Nothing;
  opPUSHTRAP, Disp;
  opPOPTRAP, Nothing;
  opRAISE, Nothing;
  opCHECK_SIGNALS, Nothing;
  opC_CALL1, Primitive;
  opC_CALL2, Primitive;
  opC_CALL3, Primitive;
  opC_CALL4, Primitive;
  opC_CALL5, Primitive;
  opC_CALLN, Uint_Primitive;
  opCONST0, Nothing;
  opCONST1, Nothing;
  opCONST2, Nothing;
  opCONST3, Nothing;
  opCONSTINT, Sint;
  opPUSHCONST0, Nothing;
  opPUSHCONST1, Nothing;
  opPUSHCONST2, Nothing;
  opPUSHCONST3, Nothing;
  opPUSHCONSTINT, Sint;
  opNEGINT, Nothing;
  opADDINT, Nothing;
  opSUBINT, Nothing;
  opMULINT, Nothing;
  opDIVINT, Nothing;
  opMODINT, Nothing;
  opANDINT, Nothing;
  opORINT, Nothing;
  opXORINT, Nothing;
  opLSLINT, Nothing;
  opLSRINT, Nothing;
  opASRINT, Nothing;
  opEQ, Nothing;
  opNEQ, Nothing;
  opLTINT, Nothing;
  opLEINT, Nothing;
  opGTINT, Nothing;
  opGEINT, Nothing;
  opOFFSETINT, Sint;
  opOFFSETREF, Sint;
  opISINT, Nothing;
  opGETMETHOD, Nothing;
  opBEQ, Sint_Disp;
  opBNEQ, Sint_Disp;
  opBLTINT, Sint_Disp;
  opBLEINT, Sint_Disp;
  opBGTINT, Sint_Disp;
  opBGEINT, Sint_Disp;
  opULTINT, Nothing;
  opUGEINT, Nothing;
  opBULTINT, Uint_Disp;
  opBUGEINT, Uint_Disp;
  opSTOP, Nothing;
  opEVENT, Nothing;
  opBREAK, Nothing;
];;

let print_event ev =
  printf "%s, line %d, char %d:\n" ev.ev_char.Lexing.pos_fname
         ev.ev_char.Lexing.pos_lnum
         (ev.ev_char.Lexing.pos_cnum - ev.ev_char.Lexing.pos_bol)

let print_instr ic =
  let pos = currpos ic in
  List.iter print_event (Hashtbl.find_all event_table pos);
  printf "%8d  " (pos / 4);
  let op = inputu ic in
  if op >= Array.length names_of_instructions || op < 0
  then (print_string "*** unknown opcode : "; print_int op)
  else print_string names_of_instructions.(op);
  print_string " ";
  begin try match List.assoc op op_shapes with
  | Uint -> print_int (inputu ic)
  | Sint -> print_int (inputs ic)
  | Uint_Uint
     -> print_int (inputu ic); print_string ", "; print_int (inputu ic)
  | Disp -> let p = currpc ic in print_int (p + inputs ic)
  | Uint_Disp
     -> print_int (inputu ic); print_string ", ";
        let p = currpc ic in print_int (p + inputs ic)
  | Sint_Disp
     -> print_int (inputs ic); print_string ", ";
        let p = currpc ic in print_int (p + inputs ic)
  | Getglobal -> print_getglobal_name ic
  | Getglobal_Uint
     -> print_getglobal_name ic; print_string ", "; print_int (inputu ic)
  | Setglobal -> print_setglobal_name ic
  | Primitive -> print_primitive ic
  | Uint_Primitive
     -> print_int(inputu ic); print_string ", "; print_primitive ic
  | Switch
     -> let n = inputu ic in
        let orig = currpc ic in
        for i = 0 to (n land 0xFFFF) - 1 do
          print_string "\n        int "; print_int i; print_string " -> ";
          print_int(orig + inputs ic);
        done;
        for i = 0 to (n lsr 16) - 1 do
          print_string "\n        tag "; print_int i; print_string " -> ";
          print_int(orig + inputs ic);
        done;
  | Closurerec
     -> let nfuncs = inputu ic in
        let nvars = inputu ic in
        let orig = currpc ic in
        print_int nvars;
        for i = 0 to nfuncs - 1 do
          print_string ", ";
          print_int (orig + inputu ic);
        done;
  | Nothing -> ()
  with Not_found -> print_string "(unknown arguments)"
  end;
  print_string "\n";
;;

(* Disassemble a block of code *)

let print_code ic len =
  start := pos_in ic;
  let stop = !start + len in
  while pos_in ic < stop do print_instr ic done

(* Dump relocation info *)

let print_reloc (info, pos) =
  printf "    %d    (%d)    " pos (pos/4);
  match info with
    Reloc_literal sc -> print_struct_const sc; printf "\n"
  | Reloc_getglobal id -> printf "require    %s\n" (Ident.name id)
  | Reloc_setglobal id -> printf "provide    %s\n" (Ident.name id)
  | Reloc_primitive s -> printf "prim    %s\n" s

(* Print a .cmo file *)

let dump_obj filename ic =
  let buffer = String.create (String.length cmo_magic_number) in
  really_input ic buffer 0 (String.length cmo_magic_number);
  if buffer <> cmo_magic_number then begin
    prerr_endline "Not an object file"; exit 2
  end;
  let cu_pos = input_binary_int ic in
  seek_in ic cu_pos;
  let cu = (input_value ic : compilation_unit) in
  reloc := cu.cu_reloc;
  if cu.cu_debug > 0 then begin
    seek_in ic cu.cu_debug;
    let evl = (input_value ic : debug_event list) in
    record_events 0 evl
  end;
  seek_in ic cu.cu_pos;
  print_code ic cu.cu_codesize

(* Read the primitive table from an executable *)

let read_primitive_table ic len =
  let p = String.create len in
  really_input ic p 0 len;
  let rec split beg cur =
    if cur >= len then []
    else if p.[cur] = '\000' then
      String.sub p beg (cur - beg) :: split (cur + 1) (cur + 1)
    else
      split beg (cur + 1) in
  Array.of_list(split 0 0)

(* Print an executable file *)

let dump_exe ic =
  Bytesections.read_toc ic;
  let prim_size = Bytesections.seek_section ic "PRIM" in
  primitives := read_primitive_table ic prim_size;
  ignore(Bytesections.seek_section ic "DATA");
  let init_data = (input_value ic : Obj.t array) in
  globals := Array.create (Array.length init_data) Empty;
  for i = 0 to Array.length init_data - 1 do
    !globals.(i) <- Constant (init_data.(i))
  done;
  ignore(Bytesections.seek_section ic "SYMB");
  let (_, sym_table) = (input_value ic : int * (Ident.t, int) Tbl.t) in
  Tbl.iter (fun id pos -> !globals.(pos) <- Global id) sym_table;
  begin try
    ignore (Bytesections.seek_section ic "DBUG");
    let num_eventlists = input_binary_int ic in
    for i = 1 to num_eventlists do
      let orig = input_binary_int ic in
      let evl = (input_value ic : debug_event list) in
      record_events orig evl
    done
  with Not_found -> ()
  end;
  let code_size = Bytesections.seek_section ic "CODE" in
  print_code ic code_size

let main() =
  for i = 1 to Array.length Sys.argv - 1 do
    let ic = open_in_bin Sys.argv.(i) in
    begin try
      objfile := false; dump_exe ic
    with Bytesections.Bad_magic_number ->
      objfile := true; seek_in ic 0; dump_obj (Sys.argv.(i)) ic
    end;
    close_in ic
  done;
  exit 0

let _ = Printexc.catch main (); exit 0
