; ============================================================
; 6809 FORTH - 01_vectors
; Part of the consolidated build; see 00_memory_map_and_globals.asm
; for shared constants and the GLOBALS layout this file depends on.
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
