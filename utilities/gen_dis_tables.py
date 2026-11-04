# Generates the DISASM tables (name pool and lookup tables) as assembler text.
RMW = ['NEG','COM','LSR','ROR','ASR','ASL','ROL','DEC','INC','TST','JMP','CLR']
BR  = ['BRA','BRN','BHI','BLS','BCC','BCS','BNE','BEQ','BVC','BVS','BPL','BMI','BGE','BLT','BGT','BLE']
MISC= ['NOP','SYNC','LBRA','LBSR','DAA','ORCC','ANDCC','SEX','EXG','TFR','LEAX','LEAY','LEAS','LEAU',
       'PSHS','PULS','PSHU','PULU','RTS','ABX','RTI','CWAI','MUL','SWI','SWI2','SWI3']
CA  = ['SUBA','CMPA','SBCA','SUBD','ANDA','BITA','LDA','STA','EORA','ADCA','ORA','ADDA','CMPX','JSR','LDX','STX']
CB  = ['SUBB','CMPB','SBCB','ADDD','ANDB','BITB','LDB','STB','EORB','ADCB','ORB','ADDB','LDD','STD','LDU','STU']
EXT = ['BSR','CMPD','CMPY','LDY','STY','LDS','STS','CMPU','CMPS','FCB']
POOL = RMW+BR+MISC+CA+CB+EXT
assert len(set(POOL)) == len(POOL), [n for n in POOL if POOL.count(n)>1]
IX = {n:i for i,n in enumerate(POOL)}
M = dict(INH=0,IMM8=1,IMM16=2,DIR=3,IDX=4,EXT=5,REL8=6,REL16=7,REG=8,STKS=9,STKU=10,FCB=11)
out = []
w = out.append
w('; Name index constants (positions in DNAMES)')
for n in ['BRA','SWI2','BSR','JMP','FCB']:
    w('N_%-6s EQU   %d' % (n, IX[n]))
for k,v in M.items():
    w('D_%-6s EQU   %d' % (k, v))
w('')
w('; DNAMES: every mnemonic once, bit 7 set on the last character.')
w('DNAMES:')
for n in POOL:
    w('            FCC   "%s"' % n[:-1] + ('' ) ) if False else None
    body = n[:-1]
    if body:
        w('            FCC   "%s"' % body)
    w('            FCB   $%02X               ; %s = %d' % (ord(n[-1])|0x80, n, IX[n]))
def fcb(lst, per=8):
    rows=[]
    for i in range(0,len(lst),per):
        rows.append('            FCB   ' + ','.join(lst[i:i+per]))
    return rows
def nm(n): return 'N_%s'%n if n in ('BRA','SWI2','BSR','JMP','FCB') else str(IX[n])
ILL='$FF'
# RMW column: low nibble -> name
rm = {0:'NEG',3:'COM',4:'LSR',6:'ROR',7:'ASR',8:'ASL',9:'ROL',0xA:'DEC',0xC:'INC',0xD:'TST',0xE:'JMP',0xF:'CLR'}
w('')
w('; DRMW: low nibble of $0x,$4x-$7x -> name ($FF = illegal)')
w('DRMW:')
out += fcb([str(IX[rm[i]]) if i in rm else ILL for i in range(16)])
w('; DRMWMD: high nibble 0..7 -> mode (4,5 = inherent on A,B)')
w('DRMWMD:')
w('            FCB   D_DIR,D_INH,D_INH,D_INH,D_INH,D_INH,D_IDX,D_EXT')
# fix: h=1,2,3 unused slots (handled elsewhere) ; h=4,5 inherent
t1 = {2:('NOP','INH'),3:('SYNC','INH'),6:('LBRA','REL16'),7:('LBSR','REL16'),9:('DAA','INH'),0xA:('ORCC','IMM8'),
      0xC:('ANDCC','IMM8'),0xD:('SEX','INH'),0xE:('EXG','REG'),0xF:('TFR','REG')}
t3 = {0:('LEAX','IDX'),1:('LEAY','IDX'),2:('LEAS','IDX'),3:('LEAU','IDX'),4:('PSHS','STKS'),5:('PULS','STKS'),
      6:('PSHU','STKU'),7:('PULU','STKU'),9:('RTS','INH'),0xA:('ABX','INH'),0xB:('RTI','INH'),0xC:('CWAI','IMM8'),
      0xD:('MUL','INH'),0xF:('SWI','INH')}
def tab(label, t, comment):
    w('')
    w(comment)
    w(label+':')
    for i in range(16):
        if i in t:
            n,m = t[i]
            w('            FCB   %d,D_%s              ; %s' % (IX[n], m, n))
        else:
            w('            FCB   $FF,0')
tab('DTAB1', t1, '; DTAB1: $1x -> (name, mode)')
tab('DTAB3', t3, '; DTAB3: $3x -> (name, mode)')
w('')
w('; DCOLS: $80-$FF columns, A side (bit 6 = 0) then B side')
w('DCOLS:')
out += fcb([str(IX[n]) for n in CA+CB])
# overrides for pages 1 and 2: key = page*64 + side*16 + column
ov = [(1,0,3,'CMPD'),(1,0,0xC,'CMPY'),(1,0,0xE,'LDY'),(1,0,0xF,'STY'),(1,1,0xE,'LDS'),(1,1,0xF,'STS'),
      (2,0,3,'CMPU'),(2,0,0xC,'CMPS')]
w('')
w('; DOVR: page 1/2 column opcodes: key = page*64+side*16+column, name; 0 ends')
w('DOVR:')
for p,s,c,n in ov:
    w('            FCB   $%02X,%d             ; %s' % (p*64+s*16+c, IX[n], n))
w('            FCB   0')
w('')
w('; DIMMT: column -> immediate mode ($FF = no immediate form)')
w('DIMMT:')
imm = []
for c in range(16):
    if c in (3,0xC,0xE): imm.append('D_IMM16')
    elif c in (7,0xD,0xF): imm.append('$FF')
    else: imm.append('D_IMM8')
out += fcb(imm)
w('; DCMODE: bits 4-5 of the opcode -> mode')
w('DCMODE:     FCB   D_IMM8,D_DIR,D_IDX,D_EXT')
w('; DREGT: TFR/EXG register code -> two characters')
w('DREGT:      FCC   "D X Y U S PC????A B CCDP"')
w('; DSTKR: PSH/PUL bit -> register code (bit 6 is replaced by U or S)')
w('DSTKR:      FCB   10,8,9,11,1,2,3,5')
w('DREGL:      FCC   "XYUS"')
w('DACC:       FCC   "?BAD"')
w('; DIXT: indexed mode (low nibble of the postbyte) -> descriptor:')
w('; bits 0-1 minus signs before the register, bits 2-3 plus signs after,')
w('; bits 4-5 accumulator (1 B, 2 A, 3 D), bit 7 = needs its own code')
w('DIXT:')
d = [0x04,0x08,0x01,0x02,0x00,0x10,0x20,0x00,0x88,0x89,0x00,0x30,0x8C,0x8D,0x00,0x8F]
out += fcb(['$%02X'%x for x in d])
open('dis_tables.inc','w').write('\n'.join(out)+'\n')
print(len(POOL), sum(len(n) for n in POOL))
