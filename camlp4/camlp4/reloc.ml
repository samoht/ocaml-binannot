(* camlp4r *)
(***********************************************************************)
(*                                                                     *)
(*                             Camlp4                                  *)
(*                                                                     *)
(*        Daniel de Rauglaudre, projet Cristal, INRIA Rocquencourt     *)
(*                                                                     *)
(*  Copyright 1998 Institut National de Recherche en Informatique et   *)
(*  Automatique.  Distributed only by permission.                      *)
(*                                                                     *)
(***********************************************************************)

(* $Id$ *)

open MLast;

value option_map f =
  fun
  [ Some x -> Some (f x)
  | None -> None ]
;

value rec ctyp floc sh =
  self where rec self =
    fun
    [ TyAcc loc x1 x2 -> TyAcc (floc loc) (self x1) (self x2)
    | TyAli loc x1 x2 -> TyAli (floc loc) (self x1) (self x2)
    | TyAny loc -> TyAny (floc loc)
    | TyApp loc x1 x2 -> TyApp (floc loc) (self x1) (self x2)
    | TyArr loc x1 x2 -> TyArr (floc loc) (self x1) (self x2)
    | TyCls loc x1 -> TyCls (floc loc) x1
    | TyLab loc x1 x2 -> TyLab (floc loc) x1 (self x2)
    | TyLid loc x1 -> TyLid (floc loc) x1
    | TyMan loc x1 x2 -> TyMan (floc loc) (self x1) (self x2)
    | TyObj loc x1 x2 ->
        TyObj (floc loc) (List.map (fun (x1, x2) -> (x1, self x2)) x1) x2
    | TyOlb loc x1 x2 -> TyOlb (floc loc) x1 (self x2)
    | TyPol loc x1 x2 -> TyPol (floc loc) x1 (self x2)
    | TyQuo loc x1 -> TyQuo (floc loc) x1
    | TyRec loc pflag x1 ->
        TyRec (floc loc) pflag
          (List.map (fun (loc, x1, x2, x3) -> (floc loc, x1, x2, self x3)) x1)
    | TySum loc pflag x1 ->
        TySum (floc loc) pflag
          (List.map (fun (loc, x1, x2) -> (floc loc, x1, List.map self x2)) x1)
    | TyTup loc x1 -> TyTup (floc loc) (List.map self x1)
    | TyUid loc x1 -> TyUid (floc loc) x1
    | TyVrn loc x1 x2 ->
        TyVrn (floc loc) (List.map (row_field floc sh) x1) x2 ]
and row_field floc sh =
  fun
  [ RfTag x1 x2 x3 -> RfTag x1 x2 (List.map (ctyp floc sh) x3)
  | RfInh x1 -> RfInh (ctyp floc sh x1) ]
;

value class_infos a floc sh x =
  {ciLoc = floc x.ciLoc; ciVir = x.ciVir;
   ciPrm =
     let (x1, x2) = x.ciPrm in
     (floc x1, x2);
   ciNam = x.ciNam; ciExp = a floc sh x.ciExp}
;

(* Debugging positions and locations *)
value eprint_pos msg p =
   Printf.eprintf "%s: fname=%s; lnum=%d; bol=%d; cnum=%d\n%!"
     msg p.Lexing.pos_fname p.Lexing.pos_lnum p.Lexing.pos_bol p.Lexing.pos_cnum
;

value eprint_loc (bp, ep) =
 do { eprint_pos "   P1" bp; eprint_pos "   P2" ep }
;
   
value check_position msg p =
   let ok =
     if (p.Lexing.pos_lnum < 0 ||
         p.Lexing.pos_bol < 0 ||
         p.Lexing.pos_cnum < 0 ||
         p.Lexing.pos_cnum < p.Lexing.pos_bol)
     then
       do {
         Printf.eprintf "*** Warning: (%s) strange position ***\n" msg;
         eprint_pos msg p;
         False
          }
     else
       True in
   (ok, p)
;

value check_location msg ((bp, ep) as loc) =
   let ok =
     let (ok1,_) = check_position "  From: " bp in
     let (ok2,_) = check_position "    To: " ep in
     if ((not ok1) || (not ok2) || 
         bp.Lexing.pos_lnum > ep.Lexing.pos_lnum ||
         bp.Lexing.pos_bol > ep.Lexing.pos_bol ||
         bp.Lexing.pos_cnum > ep.Lexing.pos_cnum)
     then
       do {
         Printf.eprintf "*** Warning: (%s) strange location ***\n" msg;
         eprint_loc loc;
         False
          }
     else
       True in
   (ok, loc)
;

(* Change a location into linear positions *)
value linearize (bp, ep) =
      ( { (bp) with Lexing.pos_lnum = 1; Lexing.pos_bol = 0 },
        { (ep) with Lexing.pos_lnum = 1; Lexing.pos_bol = 0 })
;

value shift_pos n p =
   { (p) with Lexing.pos_cnum = p.Lexing.pos_cnum + n }
;

value zero_loc =
   { (Lexing.dummy_pos) with Lexing.pos_cnum = 0; Lexing.pos_lnum = 0 };


value adjust_pos globpos local_pos =
{
  Lexing.pos_fname = globpos.Lexing.pos_fname;
  Lexing.pos_lnum = globpos.Lexing.pos_lnum + local_pos.Lexing.pos_lnum - 1;
  Lexing.pos_bol = 
      if local_pos.Lexing.pos_lnum <= 1 then
        globpos.Lexing.pos_bol
      else
        local_pos.Lexing.pos_bol + globpos.Lexing.pos_cnum;
  Lexing.pos_cnum = local_pos.Lexing.pos_cnum + globpos.Lexing.pos_cnum
};

value adjust_loc gpos (p1, p2) =
   (adjust_pos gpos p1, adjust_pos gpos p2)
;

(* Note: in the following, the "let nloc = floc loc in" is necessary
   in order to force evaluation order: the "floc" function has a side-effect
   that changes all locations produced but the first one into ghost locations *)

value rec patt floc sh =
  self where rec self =
    fun
    [ PaAcc loc x1 x2 -> let nloc = floc loc in PaAcc nloc (self x1) (self x2)
    | PaAli loc x1 x2 -> let nloc = floc loc in PaAli nloc (self x1) (self x2)
    | PaAnt loc x1 -> (* Note that antiquotations are parsed by the OCaml parser, passing line numbers and begs of lines *)
        patt (fun lloc -> adjust_loc (adjust_pos sh (fst loc)) (linearize lloc)) zero_loc x1
    | PaAny loc -> let nloc = floc loc in PaAny nloc
    | PaApp loc x1 x2 -> let nloc = floc loc in PaApp nloc (self x1) (self x2)
    | PaArr loc x1 -> let nloc = floc loc in PaArr nloc (List.map self x1)
    | PaChr loc x1 -> let nloc = floc loc in PaChr nloc x1
    | PaInt loc x1 -> let nloc = floc loc in PaInt nloc x1
    | PaInt32 loc x1 -> let nloc = floc loc in PaInt32 nloc x1
    | PaInt64 loc x1 -> let nloc = floc loc in PaInt64 nloc x1
    | PaNativeInt loc x1 -> let nloc = floc loc in PaNativeInt nloc x1
    | PaFlo loc x1 -> let nloc = floc loc in PaFlo nloc x1
    | PaLab loc x1 x2 -> let nloc = floc loc in PaLab nloc x1 (option_map self x2)
    | PaLid loc x1 -> let nloc = floc loc in PaLid nloc x1
    | PaOlb loc x1 x2 ->
        let nloc = floc loc in
        PaOlb nloc x1
          (option_map
             (fun (x1, x2) -> (self x1, option_map (expr floc sh) x2)) x2)
    | PaOrp loc x1 x2 -> let nloc = floc loc in PaOrp nloc (self x1) (self x2)
    | PaRng loc x1 x2 -> let nloc = floc loc in PaRng nloc (self x1) (self x2)
    | PaRec loc x1 ->
        let nloc = floc loc in PaRec nloc (List.map (fun (x1, x2) -> (self x1, self x2)) x1)
    | PaStr loc x1 -> let nloc = floc loc in PaStr nloc x1
    | PaTup loc x1 -> let nloc = floc loc in PaTup nloc (List.map self x1)
    | PaTyc loc x1 x2 -> let nloc = floc loc in PaTyc nloc (self x1) (ctyp floc sh x2)
    | PaTyp loc x1 -> let nloc = floc loc in PaTyp nloc x1
    | PaUid loc x1 -> let nloc = floc loc in PaUid nloc x1
    | PaVrn loc x1 -> let nloc = floc loc in PaVrn nloc x1 ]
and expr floc sh =
  self where rec self =
    fun
    [ ExAcc loc x1 x2 -> let nloc = floc loc in ExAcc nloc (self x1) (self x2)
    | ExAnt loc x1 -> (* Note that antiquotations are parsed by the OCaml parser, passing line numbers and begs of lines *)
        expr (fun lloc -> (adjust_loc (adjust_pos sh (fst loc)) (linearize lloc)))
             zero_loc x1
    | ExApp loc x1 x2 -> let nloc = floc loc in ExApp nloc (self x1) (self x2)
    | ExAre loc x1 x2 -> let nloc = floc loc in ExAre nloc (self x1) (self x2)
    | ExArr loc x1 -> let nloc = floc loc in ExArr nloc (List.map self x1)
    | ExAsf loc -> let nloc = floc loc in ExAsf nloc
    | ExAsr loc x1 -> let nloc = floc loc in ExAsr nloc (self x1)
    | ExAss loc x1 x2 -> let nloc = floc loc in ExAss nloc (self x1) (self x2)
    | ExChr loc x1 -> let nloc = floc loc in ExChr nloc x1
    | ExCoe loc x1 x2 x3 ->
        let nloc = floc loc in
        ExCoe nloc (self x1) (option_map (ctyp floc sh) x2)
          (ctyp floc sh x3)
    | ExFlo loc x1 -> let nloc = floc loc in ExFlo nloc x1
    | ExFor loc x1 x2 x3 x4 x5 ->
        let nloc = floc loc in ExFor nloc x1 (self x2) (self x3) x4 (List.map self x5)
    | ExFun loc x1 ->
        let nloc = floc loc in
        ExFun nloc
          (List.map
             (fun (x1, x2, x3) ->
                (patt floc sh x1, option_map self x2, self x3))
             x1)
    | ExIfe loc x1 x2 x3 -> let nloc = floc loc in ExIfe nloc (self x1) (self x2) (self x3)
    | ExInt loc x1 -> let nloc = floc loc in ExInt nloc x1
    | ExInt32 loc x1 -> let nloc = floc loc in ExInt32 nloc x1
    | ExInt64 loc x1 -> let nloc = floc loc in ExInt64 nloc x1
    | ExNativeInt loc x1 -> let nloc = floc loc in ExNativeInt nloc x1
    | ExLab loc x1 x2 -> let nloc = floc loc in ExLab nloc x1 (option_map self x2)
    | ExLaz loc x1 -> let nloc = floc loc in ExLaz nloc (self x1)
    | ExLet loc x1 x2 x3 ->
        let nloc = floc loc in
        ExLet nloc x1
          (List.map (fun (x1, x2) -> (patt floc sh x1, self x2)) x2) (self x3)
    | ExLid loc x1 -> let nloc = floc loc in ExLid nloc x1
    | ExLmd loc x1 x2 x3 ->
        let nloc = floc loc in ExLmd nloc x1 (module_expr floc sh x2) (self x3)
    | ExMat loc x1 x2 ->
        let nloc = floc loc in
        ExMat nloc (self x1)
          (List.map
             (fun (x1, x2, x3) ->
                (patt floc sh x1, option_map self x2, self x3))
             x2)
    | ExNew loc x1 -> let nloc = floc loc in ExNew nloc x1
    | ExObj loc x1 x2 ->
        let nloc = floc loc in ExObj nloc (option_map (patt floc sh) x1)
          (List.map (class_str_item floc sh) x2)
    | ExOlb loc x1 x2 -> let nloc = floc loc in ExOlb nloc x1 (option_map self x2)
    | ExOvr loc x1 ->
        let nloc = floc loc in
        ExOvr nloc (List.map (fun (x1, x2) -> (x1, self x2)) x1)
    | ExRec loc x1 x2 ->
        let nloc = floc loc in
        ExRec nloc
          (List.map (fun (x1, x2) -> (patt floc sh x1, self x2)) x1)
          (option_map self x2)
    | ExSeq loc x1 -> let nloc = floc loc in ExSeq nloc (List.map self x1)
    | ExSnd loc x1 x2 -> let nloc = floc loc in ExSnd nloc (self x1) x2
    | ExSte loc x1 x2 -> let nloc = floc loc in ExSte nloc (self x1) (self x2)
    | ExStr loc x1 -> let nloc = floc loc in ExStr nloc x1
    | ExTry loc x1 x2 ->
        let nloc = floc loc in
        ExTry nloc (self x1)
          (List.map
             (fun (x1, x2, x3) ->
                (patt floc sh x1, option_map self x2, self x3))
             x2)
    | ExTup loc x1 -> let nloc = floc loc in ExTup nloc (List.map self x1)
    | ExTyc loc x1 x2 -> let nloc = floc loc in ExTyc nloc (self x1) (ctyp floc sh x2)
    | ExUid loc x1 -> let nloc = floc loc in ExUid nloc x1
    | ExVrn loc x1 -> let nloc = floc loc in ExVrn nloc x1
    | ExWhi loc x1 x2 -> let nloc = floc loc in ExWhi nloc (self x1) (List.map self x2) ]
and module_type floc sh =
  self where rec self =
    fun
    [ MtAcc loc x1 x2 -> let nloc = floc loc in MtAcc nloc (self x1) (self x2)
    | MtApp loc x1 x2 -> let nloc = floc loc in MtApp nloc (self x1) (self x2)
    | MtFun loc x1 x2 x3 -> let nloc = floc loc in MtFun nloc x1 (self x2) (self x3)
    | MtLid loc x1 -> let nloc = floc loc in MtLid nloc x1
    | MtQuo loc x1 -> let nloc = floc loc in MtQuo nloc x1
    | MtSig loc x1 -> let nloc = floc loc in MtSig nloc (List.map (sig_item floc sh) x1)
    | MtUid loc x1 -> let nloc = floc loc in MtUid nloc x1
    | MtWit loc x1 x2 ->
        let nloc = floc loc in MtWit nloc (self x1) (List.map (with_constr floc sh) x2) ]
and sig_item floc sh =
  self where rec self =
    fun
    [ SgCls loc x1 ->
        let nloc = floc loc in SgCls nloc (List.map (class_infos class_type floc sh) x1)
    | SgClt loc x1 ->
        let nloc = floc loc in SgClt nloc (List.map (class_infos class_type floc sh) x1)
    | SgDcl loc x1 -> let nloc = floc loc in SgDcl nloc (List.map self x1)
    | SgDir loc x1 x2 -> let nloc = floc loc in SgDir nloc x1 x2
    | SgExc loc x1 x2 -> let nloc = floc loc in SgExc nloc x1 (List.map (ctyp floc sh) x2)
    | SgExt loc x1 x2 x3 -> let nloc = floc loc in SgExt nloc x1 (ctyp floc sh x2) x3
    | SgInc loc x1 -> let nloc = floc loc in SgInc nloc (module_type floc sh x1)
    | SgMod loc x1 x2 -> let nloc = floc loc in SgMod nloc x1 (module_type floc sh x2)
    | SgRecMod loc xxs
        -> let nloc = floc loc in SgRecMod nloc (List.map (fun (x1,x2) -> (x1, (module_type floc sh x2))) xxs)
    | SgMty loc x1 x2 -> let nloc = floc loc in SgMty nloc x1 (module_type floc sh x2)
    | SgOpn loc x1 -> let nloc = floc loc in SgOpn nloc x1
    | SgTyp loc x1 ->
        let nloc = floc loc in
        SgTyp nloc
          (List.map
             (fun ((loc, x1), x2, x3, x4) ->
                ((floc loc, x1), x2, ctyp floc sh x3,
                 List.map (fun (x1, x2) -> (ctyp floc sh x1, ctyp floc sh x2))
                   x4))
             x1)
    | SgUse loc x1 x2 -> SgUse loc x1 x2
    | SgVal loc x1 x2 -> let nloc = floc loc in SgVal nloc x1 (ctyp floc sh x2) ]
and with_constr floc sh =
  self where rec self =
    fun
    [ WcTyp loc x1 x2 x3 -> let nloc = floc loc in WcTyp nloc x1 x2 (ctyp floc sh x3)
    | WcMod loc x1 x2 -> let nloc = floc loc in WcMod nloc x1 (module_expr floc sh x2) ]
and module_expr floc sh =
  self where rec self =
    fun
    [ MeAcc loc x1 x2 -> let nloc = floc loc in MeAcc nloc (self x1) (self x2)
    | MeApp loc x1 x2 -> let nloc = floc loc in MeApp nloc (self x1) (self x2)
    | MeFun loc x1 x2 x3 ->
        let nloc = floc loc in
        MeFun nloc x1 (module_type floc sh x2) (self x3)
    | MeStr loc x1 -> let nloc = floc loc in MeStr nloc (List.map (str_item floc sh) x1)
    | MeTyc loc x1 x2 -> let nloc = floc loc in MeTyc nloc (self x1) (module_type floc sh x2)
    | MeUid loc x1 -> let nloc = floc loc in MeUid nloc x1 ]
and str_item floc sh =
  self where rec self =
    fun
    [ StCls loc x1 ->
        let nloc = floc loc in StCls nloc (List.map (class_infos class_expr floc sh) x1)
    | StClt loc x1 ->
        let nloc = floc loc in StClt nloc (List.map (class_infos class_type floc sh) x1)
    | StDcl loc x1 -> let nloc = floc loc in StDcl nloc (List.map self x1)
    | StDir loc x1 x2 -> let nloc = floc loc in StDir nloc x1 x2
    | StExc loc x1 x2 x3 -> let nloc = floc loc in StExc nloc x1 (List.map (ctyp floc sh) x2) x3
    | StExp loc x1 -> let nloc = floc loc in StExp nloc (expr floc sh x1)
    | StExt loc x1 x2 x3 -> let nloc = floc loc in StExt nloc x1 (ctyp floc sh x2) x3
    | StInc loc x1 -> let nloc = floc loc in StInc nloc (module_expr floc sh x1)
    | StMod loc x1 x2 -> let nloc = floc loc in StMod nloc x1 (module_expr floc sh x2)
    | StRecMod loc nmtmes ->
        let nloc = floc loc in StRecMod nloc (List.map (fun (n, mt, me) -> (n, module_type floc sh mt, module_expr floc sh me)) nmtmes)
    | StMty loc x1 x2 -> let nloc = floc loc in StMty nloc x1 (module_type floc sh x2)
    | StOpn loc x1 -> let nloc = floc loc in StOpn nloc x1
    | StTyp loc x1 ->
        let nloc = floc loc in
        StTyp nloc
          (List.map
             (fun ((loc, x1), x2, x3, x4) ->
                ((floc loc, x1), x2, ctyp floc sh x3,
                 List.map (fun (x1, x2) -> (ctyp floc sh x1, ctyp floc sh x2))
                   x4))
             x1)
    | StUse loc x1 x2 -> StUse loc x1 x2
    | StVal loc x1 x2 ->
        let nloc = floc loc in StVal nloc x1
          (List.map (fun (x1, x2) -> (patt floc sh x1, expr floc sh x2)) x2) ]
and class_type floc sh =
  self where rec self =
    fun
    [ CtCon loc x1 x2 -> let nloc = floc loc in CtCon nloc x1 (List.map (ctyp floc sh) x2)
    | CtFun loc x1 x2 -> let nloc = floc loc in CtFun nloc (ctyp floc sh x1) (self x2)
    | CtSig loc x1 x2 ->
        let nloc = floc loc in
        CtSig nloc (option_map (ctyp floc sh) x1)
          (List.map (class_sig_item floc sh) x2) ]
and class_sig_item floc sh =
  self where rec self =
    fun
    [ CgCtr loc x1 x2 -> let nloc = floc loc in CgCtr nloc (ctyp floc sh x1) (ctyp floc sh x2)
    | CgDcl loc x1 -> let nloc = floc loc in CgDcl nloc (List.map (class_sig_item floc sh) x1)
    | CgInh loc x1 -> let nloc = floc loc in CgInh nloc (class_type floc sh x1)
    | CgMth loc x1 x2 x3 -> let nloc = floc loc in CgMth nloc x1 x2 (ctyp floc sh x3)
    | CgVal loc x1 x2 x3 -> let nloc = floc loc in CgVal nloc x1 x2 (ctyp floc sh x3)
    | CgVir loc x1 x2 x3 -> let nloc = floc loc in CgVir nloc x1 x2 (ctyp floc sh x3) ]
and class_expr floc sh =
  self where rec self =
    fun
    [ CeApp loc x1 x2 -> let nloc = floc loc in CeApp nloc (self x1) (expr floc sh x2)
    | CeCon loc x1 x2 -> let nloc = floc loc in CeCon nloc x1 (List.map (ctyp floc sh) x2)
    | CeFun loc x1 x2 -> let nloc = floc loc in CeFun nloc (patt floc sh x1) (self x2)
    | CeLet loc x1 x2 x3 ->
        let nloc = floc loc in
        CeLet nloc x1
          (List.map (fun (x1, x2) -> (patt floc sh x1, expr floc sh x2)) x2)
          (self x3)
    | CeStr loc x1 x2 ->
        let nloc = floc loc in CeStr nloc (option_map (patt floc sh) x1)
          (List.map (class_str_item floc sh) x2)
    | CeTyc loc x1 x2 -> let nloc = floc loc in CeTyc nloc (self x1) (class_type floc sh x2) ]
and class_str_item floc sh =
  self where rec self =
    fun
    [ CrCtr loc x1 x2 -> let nloc = floc loc in CrCtr nloc (ctyp floc sh x1) (ctyp floc sh x2)
    | CrDcl loc x1 -> let nloc = floc loc in CrDcl nloc (List.map (class_str_item floc sh) x1)
    | CrInh loc x1 x2 -> let nloc = floc loc in CrInh nloc (class_expr floc sh x1) x2
    | CrIni loc x1 -> let nloc = floc loc in CrIni nloc (expr floc sh x1)
    | CrMth loc x1 x2 x3 x4 ->
        let nloc = floc loc in CrMth nloc x1 x2 (expr floc sh x3) (option_map (ctyp floc sh) x4)
    | CrVal loc x1 x2 x3 -> let nloc = floc loc in CrVal nloc x1 x2 (expr floc sh x3)
    | CrVir loc x1 x2 x3 -> let nloc = floc loc in CrVir nloc x1 x2 (ctyp floc sh x3) ]
;
