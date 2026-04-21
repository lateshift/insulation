;;;  InsulBattPoly.LSP [Command name: IB]
;;;  To draw a lightweight Polyline representation of Batt Insulation.
;;;  Draws a zero-width continuous LWPolyline as a series of S-curves, alternating direction and forming
;;;    touching loops.  Intermediate point locations are adjusted for localized path direction on curved
;;;    paths, narrowing inside-of-curve loops and widening outside-of-curve loops to eliminate overlaps
;;;    or gaps.  [Non-tangent changes in direction in Polyline paths, or overly tight curves relative to
;;;    insulation thickness in various entity types, or non- Centered justification with Polylines or Splines
;;;    that intersect (or relative to insulation thickness, get too close to) themselves, will yield quirky results.]
;;;  Divides path length into whole S-curve "length" increments to eliminate need for trimming at ends
;;;    (other than for e.g. ventilation-baffle taper); forces an even number of S's for closed paths so that result
;;;    looks continuous across start/end point (will be a tiny gap on tangent-closed Pline path -- see slength).
;;;  Draws on current Layer, unless Deleting pre-Existing path; if so, draws on its Layer, assuming the
;;;    intent is to replace it (e.g. to replace something with BATTING linetype).
;;;  Under select-Existing option, asks User to select again if nothing is selected, or if selected object is an
;;;    inappropriate entity type.
;;;  Accounts for different Coordinate Systems.
;;;  Remembers option choices and offers them as defaults for subsequent use.
;;;  Options:
;;;    1.  create new within the routine, or select pre-Existing, path of any 2D finite type with linearity;
;;;    2.  if selected Existing object is on a locked Layer, whether to unlock it and Proceed, or Quit;
;;;    3.  PRevious = redraw along prior path (whether retained or deleted) allowing different choices;
;;;    4.  Flip = one-step replacement of prior result, if Left- or Right-justified, on other side -- meant for
;;;         Existing Line/Pline/Spline (drawing direction not visually apparent), but works on all types;
;;;    5.  Retain or Delete base path, whether new or selected Existing;
;;;    6.  insulation thickness, with some pre-defined [US] common-thickness options;
;;;    7.  Center-line or Left- or Right-side justification (Left & Right are relative to drawing direction
;;;         for Line/Pline/Spline; for Arc/Circle/Ellipse, Left draws inside, Right draws outside).
;;;
;;;  Kent Cooper, last edited March 2010
;
(vl-load-com)
;
(defun ibreset ()
  (setvar 'osmode osm)
  (setvar 'blipmode blips)
  (setvar 'plinewid plwid)
  (setvar 'plinetype pltyp)
  (setvar 'celtype ltyp)
  (command "_.undo" "_end")
  (setvar 'cmdecho cmde)
); end defun - ibreset
;
(defun locdir (path dist); LOCal DIRection of path at distance along it, accounting for UCS
  (angle
    '(0 0 0)
    (trans
      (vlax-curve-getFirstDeriv
        path
        (vlax-curve-getParamAtDist path dist)
      ); end getFirstDeriv
      0 1 T ; world to current CS, as displacement
    ); end trans
  ); end angle
); end defun - locdir
;
(defun ibpt (advpro offpro)
;;  This subroutine calculates an Insulation-Batt polyline definition PoinT, with arguments:
;;    advpro = localized amount of ADVance from current S-curve segment's basepoint along path,
;;      as a PROportion of segment length
;;    offpro = localized amount of OFFset to side from path, as a PROportion of thickness
  (polar
    (trans
      (vlax-curve-getPointAtDist ; advance point along working path
        ibtpath
        (+
          (vlax-curve-getDistAtPoint ibtpath sbase)
          (* advpro slength); proportion of segment length
        ); end +
      ); end getPointAtDist
      0 1 ; from World coordinates to object's coordinates
    ); end trans
    (+ ; localized angle of offset
      (locdir
        ibtpath
        (+
          (vlax-curve-getDistAtPoint ibtpath sbase)
          (* advpro slength)
        ); end +
      ); end locdir
      (* pi 0.5 side); perpendicular to center-line path [side +/- gives left/right]
    ); end +
    (* offpro *ibthk*); proportion of insulation thickness
  ); end polar
); end defun - ibpt
;
(defun ibptend (offpro)
;;  This subroutine calculates an Insulation-Batt polyline definition PoinT, aligned with the
;;  END of the path, to avoid possible failure from calculation-rounding going beyond end
;;  [except in closed Plines - see slength], with offpro argument as above
  (polar
    (trans (vlax-curve-getEndPoint ibtpath) 0 1)
    (+ ; localized angle of offset
      ; following instead of (locdir ibtpath pathlength), because that fails at end of "heavy"
      ; 2D Polyline -- somehow (vlax-curve-getParamAtDist ibtpath pathlength) returns nil
      (angle
        '(0 0 0)
        (trans
          (vlax-curve-getFirstDeriv
            ibtpath
            (vlax-curve-getEndParam ibtpath)
          ); end getFirstDeriv
          0 1 T ; world to current CS, as displacement
        ); end trans
      ); end angle
      (* pi 0.5 side); perpendicular to center-line path [side +/- gives left/right]
    ); end +
    (* offpro *ibthk*); proportion of insulation thickness
  ); end polar
); end defun - ibptend
;
;;; ******************************** Main Routine: IB ********************************
(defun C:IB
  (/ *error* cmde osm blips plwid pltyp ltyp typetemp pathsel pathdata pathtype
  polyclosed unlktemp deltemp thktemp justtemp ucschanged ptno side pldist
  plpt ibtpath pathlength isCurved vertcheck vertbulge sbase ssegs slength)
;
  (defun *error* (errmsg)
    (if (not (wcmatch errmsg "Function cancelled,quit / exit abort"))
      (princ (strcat "\nError: " errmsg))
    ); end if
    (command)
    (command)
    (if ucschanged (command "_.ucs" "_prev"))
      ; ^ i.e. don't go back unless routine reached UCS change but didn't change it back
    (ibreset)
  ); end defun - *error*
;
  (command "_.undo" "_begin")
  (setq cmde (getvar 'cmdecho))
  (setvar 'cmdecho 0)
  (setq
    osm (getvar 'osmode)
    blips (getvar 'blipmode)
    plwid (getvar 'plinewid)
    pltyp (getvar 'plinetype)
    ltyp (getvar 'celtype)
  ); end setq
  (setvar 'plinewid 0)
  (setvar 'plinetype 2)
  (setvar 'celtype "CONTINUOUS")
;
  (initget
    (strcat
      "Existing Line Arc Circle Pline ELlipse Spline"
      (if *ibtype* " PRevious" ""); add PR option only if not first use
      (if (member *ibjust* '("Left" "Right")) " Flip" ""); add Flip option only if prior was L/R
    ); end strcat
  ); end initget
  (setq
    typetemp
      (getkword
        (strcat
          "\nPath type [Existing, or new Line(single)/Arc/Circle/Pline/ELlipse/Spline"
          (if *ibtype* "/PRevious" ""); offer PR option if not first use
          (if (member *ibjust* '("Left" "Right")) "/Flip" ""); add Flip option only if prior was L/R
          "] <"
          (if *ibtype* *ibtype* "Line"); prior choice default if applicable; otherwise Line
          ">: "
        ); end strcat
      ); end getkword & typetemp
    *ibtype*
      (cond
        (typetemp); if User typed something other than Enter, use it
        (*ibtype*); if Enter and there's a prior choice, use that
        (T "Line"); otherwise [Enter on first use], Line default
      ); end cond & *ibtype*
  ); end setq
;
  (if
    (and (wcmatch *ibtype* "PRevious,Flip") *isLocked*)
    (command "_.layer" "_unlock" *pathlay* ""); then - unlock layer without asking [prior Proceed option]
  ); end if
;
  (cond ; select or make path
    ((= *ibtype* "Existing")
      (while
        (not
          (and
            (setq
              pathsel (car (entsel "\nSelect object to draw batt insulation along an Existing path: "))
              pathdata (if pathsel (entget pathsel))
              pathtype (if pathsel (substr (cdr (assoc 100 (cdr (member (assoc 100 pathdata) pathdata)))) 5))
                ; ^ = entity type from second (assoc 100) without "AcDb" prefix;  using this because (assoc 0)
                ; value is the same for 2D & 3D Polylines; 2D OK, but not 3D because they can't be offset,
                ; so only center justification could be offered, and result would be flattened in current CS
            ); end setq
            (wcmatch pathtype "Line,Arc,Circle,Ellipse,Spline,Polyline,2dPolyline")
          ); end and
        ); end not
        (prompt "\nNothing selected, or it is not a 2D finite path type; try again:")
      ); end while
    ); end first condition - Existing
    ((and (wcmatch *ibtype* "PRevious,Flip") (= *ibdel* "Delete")) (entdel *ibpath*)); bring back prior
    ((= *ibtype* "Line") (setvar 'cmdecho 1) (command "_.line" pause pause "") (setvar 'cmdecho 0))
    ((not (wcmatch *ibtype* "PRevious,Flip")); all other entity types
      (setvar 'cmdecho 1)
      (command *ibtype*)
      (while (> (getvar 'cmdactive) 0) (command pause))
      (setvar 'cmdecho 0)
    ); end fourth condition
  ); end cond
  (setvar 'blipmode 0)
;
  (setq
    *ibpath* ; set object as base path [not localized, so it can be brought back if PR/F and D options]
      (cond
        ((= *ibtype* "Existing") pathsel); selected object
        ((wcmatch *ibtype* "PRevious,Flip") *ibpath*); keep the same
        ((entlast)); otherwise, newly created path
      ); end cond & *ibpath*
    pathdata (entget *ibpath*)
    pathtype (cdr (assoc 0 pathdata)); can now use this, once past possibility of selecting 3D Polyline
    polyclosed ; used in offsetting and segment-length determinations
      (and
        (wcmatch pathtype "*POLYLINE"); allow for "heavy" 2D or "lightweight" Polylines
        (vlax-curve-isClosed *ibpath*)
      ); end and
    *pathlay* (cdr (assoc 8 pathdata))
      ; ^ not localized, so that under PRevious or Flip options, knows what layer to unlock if needed
    *isLocked* ; not localized, so that under PRevious or Flip options, don't need to ask again
      (if (and (wcmatch *ibtype* "PRevious,Flip") *isLocked*)
        T ; keep with PR/F if prior object was on locked layer
        (/= (cdr (assoc 70 (tblsearch "layer" *pathlay*))) 0); other types - 0 for Unlocked: nil; 4 for Locked: T
      ); end if & *isLocked*
  ); end setq
;
  (if *isLocked*
    (if (not (wcmatch *ibtype* "PRevious,Flip")); then - check for not redoing prior object  
      (progn ; then - ask whether to unlock
        (initget "Proceed Quit")
        (setq
          unlktemp
            (getkword
              (strcat
                "\nLayer is locked; temporarily unlock and Proceed, or Quit? [P/Q] <"
                (if *ibunlk* (substr *ibunlk* 1 1) "P"); at first use, Proceed default; otherwise, prior choice
                ">: "
              ); end strcat
            ); end getkword & unlktemp
          *ibunlk*
            (cond
              (unlktemp); if User typed something, use it
              (*ibunlk*); if Enter and there's a prior choice, keep that
              (T "Proceed"); otherwise [Enter on first use], Proceed
            ); end cond & *ibunlk*
        ); end setq
        (if (= *ibunlk* "Proceed")
          (command "_.layer" "_unlock" *pathlay* ""); then
          (progn (ibreset) (quit)); else
        ); end if
      ); end progn & inner else argument
    ); end inner if & outer then argument
  ); end outer if - no else argument [no issue if not on locked layer]
;
  (if (wcmatch *ibtype* "PRevious,Flip") (entdel *ib*))
    ; ^ if re-using Previous path with new choices, or Flipping to other side, delete previous result
;
  (if (/= *ibtype* "Flip")
    (progn ; then - ask whether to Retain or Delete if not Flipping
      (initget "Retain Delete")
      (setq
        deltemp
          (getkword
            (strcat
              "\nRetain or Delete base path [R/D] <"
              (if *ib* (substr *ibdel* 1 1) "D"); at first use, Delete default; otherwise, prior choice
              ">: "
            ); end strcat
          ); end getkword
        *ibdel*
          (cond
            (deltemp); if User typed something, use it
            (*ibdel*); if Enter and there's a prior choice, keep that
            (T "Delete"); otherwise [Enter on first use], Delete
          ); end cond & *ibdel*
      ); end setq
    ); end progn
  ); end if -- no else argument [keep previous option if Flipping]
;
  (if (/= *ibtype* "Flip")
    (progn ; then - ask for thickness if not Flipping
      (initget (if *ibthk* 6 7) "A B C D"); no Enter on first use, no 0, no negative
      (setq
        thktemp
          (getdist
            (strcat
              "\nThickness of insulation batting, or [A=3.5/B=5.5/C=9.5/D=12]"
              (if *ibthk* (strcat " <" (rtos *ibthk* 2 2) ">") ""); default only if not first use
              ": "
            ); end strcat
          ); end getdist & thktemp
        *ibthk*
          (cond
            ((= thktemp "A") 3.5)
            ((= thktemp "B") 5.5)
            ((= thktemp "C") 9.5)
            ((= thktemp "D") 12.0)
            ((numberp thktemp) thktemp); user entered number or picked distance
            (T *ibthk*); otherwise, user hit Enter - keep value
          ); end cond & *ibthk*
      ); end setq
    ); end progn
  ); end if -- no else argument [keep previous thickness if Flipping]
;
  (if (/= *ibtype* "Flip")
    (progn ; then - ask for justification if not Flipping
      (initget "Center Left Right")
      (setq
        justtemp
          (getkword
            (strcat
              "\nJustification [Center/Left(inside arc,circle,ellipse)/Right(outside)] <"
              (if *ibjust* (substr *ibjust* 1 1) "C"); at first use, Center default; otherwise, prior choice
              ">: "
            ); end strcat
          ); end getkword
        *ibjust*
          (cond
            (justtemp); if User typed something, use it
            (*ibjust*); if Enter and there's a prior choice, use that
            (T "Center"); otherwise [Enter on first use], Center
          ); end cond & *ibjust*
      ); end setq
    ); end progn
    (setq *ibjust* (if (= *ibjust* "Left") "Right" "Left")); else - reverse justification if Flipping
  ); end if
;
  (command "_.ucs" "_new" "_object" *ibpath*) ; set UCS to match object
  (setq
    ucschanged T ; marker for *error* to reset UCS if routine doesn't get to it
    ptno 0 ; starting point-number value for intermediate point multiplier
    side 1 ; starting directional multiplier for 'side' [left/right of center-path] argument in (ibpt)
  ); end setq
;
  (setvar 'osmode 0); placed here so running Osnap can be used to draw path, if desired
;
  (if (= *ibjust* "Center")
    (command "_.copy" *ibpath* "" '(0 0 0) '(0 0 0)); then - copy in place for Center justification
    (command ; else - offset by half insulation thickness for Left or Right justification
      "_.offset"
      (/ *ibthk* 2)
      *ibpath*
      (polar
        (if polyclosed ; less risk of inside-offsetting Plines closing at acute angles wrongly to outside
          (setq ; then - partway in
            pldist (vlax-curve-getDistAtParam *ibpath* 0.5)
            plpt (trans (vlax-curve-getPointAtParam *ibpath* 0.5) 0 1)
          ); end setq
          (trans (vlax-curve-getStartPoint *ibpath*) 0 1); else - start point
        ); end if - point argument
        (apply
          (if (= *ibjust* "Left") '+ '-); add for Left, subtract for Right
          (list (locdir *ibpath* (if polyclosed pldist 0)) (/ pi 2)); partway into closed Pline; else, startpoint
        ); end apply - angle argument
        0.1 ; distance
      ); end polar
      "" ; end offset
    ); end command - offset & else argument
  ); end if
;
  (setq
    ibtpath (entlast); save as Temporary [working] PATH
    pathlength (vlax-curve-getDistAtParam ibtpath (vlax-curve-getEndParam ibtpath))
    isCurved
        ; Determine whether path has any curves, calling for more definition points - without them,
        ; widened curves on outside of curved paths bulge beyond insulation thickness [even with
        ; them, this can still happen very slightly, if path curves sharply enough relative to thickness]
      (cond
        ((= pathtype "LINE") nil); Lines are never curved
        ((= pathtype "LWPOLYLINE"); check LWPolylines for arc segments
          (if
            (vl-remove-if-not ; recognize only non-0 bulge factors
              '(lambda (x) (and (= (car x) 42) (/= (cdr x) 0.0)))
              pathdata
            ); end vl-remove-if-not; returns list only if there are arc segments
            T ; contains at least one arc segment
            nil ; all line segments
          ); end if
        ); end LWPolyline condition
        ((= pathtype "POLYLINE"); check heavy 2D Polylines for arc segments
          (setq vertcheck (entnext ibtpath))
          (while
            (and
              (not vertbulge)
              (= (cdr (assoc 0 (entget vertcheck))) "VERTEX")
            ); end and
            (setq
              vertbulge (/= (cdr (assoc 42 (entget vertcheck))) 0.0); T if bulge factor
              vertcheck (entnext vertcheck)
            ); end setq
          ); end while
          vertbulge
        ); end heavy 2D Polyline condition
        (T) ; Arc/Circle/Ellipse/Spline are always curved
      ); end cond & isCurved
    sbase (vlax-curve-getStartPoint ibtpath); startpoint is first S-curve BASE point
    ssegs ; closed paths need even numbers of S-SEGmentS; open can have odd number
      (if (vlax-curve-isClosed *ibpath*)
        (* (fix (+ (/ pathlength *ibthk* 0.4) 0.5)) 2); then - round to nearest *even* number
        (fix (+ (/ pathlength *ibthk* 0.2) 0.5)); else - round to nearest *whole* number
      ); end if & ssegs
    slength ; proportioned S-segment LENGTH
      (/ pathlength
        (if polyclosed ; First derivative returns nil at end parameter of closed LWPolyline, causing failure
            ; of angle calculation,  so in that case,
          (+ ssegs 0.001); then - shorten segment length very slightly [results in tiny gap at tangent closure]
          ssegs ; else - divisor is unadjusted number of segments
        ); end if
      ); end / & pathlength
  ); end setq
;
  (if (= *ibdel* "Delete") (setvar 'clayer *pathlay*)) ; if Deleting Existing path, draw on same Layer
;
  (command
    "_.pline"
    (ibpt 0 0.5); start point of first S-curve
    "_arc"
    (while (< ptno ssegs)
      (setq
        sbase (vlax-curve-getPointAtDist ibtpath (* slength ptno)); incremented base along path for S segment
        ptno (1+ ptno); increment point number for next time [put here so it's not last function in (while) loop]
      ); end setq
      (command "_second")
      (if isCurved
        (command ; then - more definition points for curved paths
          (ibpt 0.3 0.49); second point of first shorter curve
          (ibpt 0.6 0.46); third point of first shorter curve
          "_second"
        ); end interim command
      ); end if [no else - continue to next second-point designation]
      (command
        (ibpt 0.8 0.42); second point of [second shorter, or first longer] curve
        (if (and (= ptno ssegs) (not polyclosed)); third point of curve at touch-point
          (ibptend 0.3); then - at end if not closed Pline
          (ibpt 1.0 0.3); else - intermediate, or end of closed Pline
        ); end if
        "_second"
        (ibpt 0.9 0.19); second point of next curve
        (ibpt 0.8 0.14); third point of next curve
        "_line"
      ); end interim command
      (setq side (- side)); for second half of S-curve on other side of path
      (command
        (ibpt 0.2 0.14); feed end of cross-the-path line segment out to Pline
        "_arc" "_second"
        (ibpt 0.1 0.19); second point of first curve
        (ibpt 0 0.3); third point of first curve at touch-point
        "_second"
        (ibpt 0.2 0.42); second point of curve after touch-point
      ); end interim command
      (if isCurved ; then - more definition points for curved paths
        (command
          (ibpt 0.4 0.46); third point of first shorter curve
          "_second"
          (ibpt 0.7 0.49); second point of second shorter curve
        ); end interim command
      ); end if [no else - continue to next second-point designation]
      (command
        (if (and (= ptno ssegs) (not polyclosed)); third point of last curve in overall S-curve
          (ibptend 0.5); then - at end if not closed Pline
          (ibpt 1.0 0.5); else - intermediate, or end of closed Pline
        ); end if
      ); end command
    ); end while
  ); end command - pline
;
  (command "_.ucs" "_prev")
  (setq
    ucschanged nil ; eliminate UCS reset in *error* since routine did it already
    *ib* (entlast); save result in case of recall of routine with PRevious or Flip option
  ); end setq
  (entdel ibtpath); remove temporary working path
  (if (= *ibdel* "Delete") (entdel *ibpath*)); remove base path under Delete option
;
  (if (and (wcmatch *ibtype* "Existing,PRevious,Flip") (= *ibdel* "Delete")) (command "_.layerp"))
    ; ^ reset Layer if appropriate
  (if *isLocked* (command "_.layer" "_lock" *pathlay* "")); re-lock layer if appropriate
  (ibreset)
  (princ)
); end defun - IB
(prompt "Type IB to make polyline-form Insulation Batting.")

