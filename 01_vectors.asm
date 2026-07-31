; ============================================================
; SECTION 1: HARDWARE VECTOR TABLE
; ============================================================
         ORG   VECTORS       ; VECTORS is $FFF0
VRESV    FDB   $0000
VSWI3    FDB   SWI3H
VSWI2    FDB   SWI2H
VFIRQ    FDB   FIRQH
VIRQ     FDB   IRQH
VSWI     FDB   SWIH
VNMI     FDB   WARM            ; NMI -> warm restart
VRESET   FDB   COLDSTRT

VECTOREND  EQU   *          ; Verify vectors size, value should match $10.
VECTORSIZE EQU   VECTOREND-VECTORS

; ============================================================
; END OF CONSOLIDATED SOURCE
; ============================================================
