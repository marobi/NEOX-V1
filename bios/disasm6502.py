#!/usr/bin/env python3
import re
import sys


def usage() -> None:
    print("usage: disasm6502.py rom.bin base [mapfile] [labelfile]")
    sys.exit(1)


if len(sys.argv) < 3:
    usage()

romfile = sys.argv[1]
basearg = sys.argv[2]
mapfile = sys.argv[3] if len(sys.argv) > 3 else None
labelfile = sys.argv[4] if len(sys.argv) > 4 else None

labels = {}
auto_labels = {}


# ------------------------------------------------
# parse base address
# accepts:
#   C000
#   0xC000
#   $C000
# ------------------------------------------------

def parse_base(text: str) -> int:
    s = text.strip().upper()
    if s.startswith("$"):
        s = s[1:]
    if s.startswith("0X"):
        s = s[2:]
    return int(s, 16) & 0xFFFF


base = parse_base(basearg)


# ------------------------------------------------
# parse label address safely
# Accept:
#   C0BD
#   00C0BD
#   0000C0BD
# Always reduce to 16-bit
# ------------------------------------------------

def parse_label_addr(text: str):
    s = text.strip().upper()

    if s.startswith("$"):
        s = s[1:]

    if not re.fullmatch(r"[0-9A-F]+", s):
        return None

    try:
        value = int(s, 16)
    except ValueError:
        return None

    return value & 0xFFFF


# ------------------------------------------------
# load .lbl symbols
# ------------------------------------------------

if labelfile:
    with open(labelfile, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            p = line.strip().split()

            if len(p) < 3:
                continue
            if p[0] != "al":
                continue

            addr = parse_label_addr(p[1])
            if addr is None:
                continue

            name = p[2].lstrip(".")

            if addr not in labels:
                labels[addr] = name


# ------------------------------------------------
# optionally enrich labels from map exports
# ------------------------------------------------

if mapfile:
    in_exports = False

    with open(mapfile, "r", encoding="utf-8", errors="replace") as f:
        for raw in f:
            line = raw.rstrip("\n")

            if line.strip() == "Exports list by name:":
                in_exports = True
                continue

            if not in_exports:
                continue

            if not line.strip():
                continue

            if line.startswith("Exports list by value:"):
                break
            if line.startswith("Imports list:"):
                break
            if line.startswith("-----"):
                continue

            p = line.split()
            if len(p) < 2:
                continue

            name = p[0]
            addr = parse_label_addr(p[1])

            if addr is None:
                continue

            if addr not in labels:
                labels[addr] = name


# ------------------------------------------------
# opcode table - legal W65C02S opcodes
# ------------------------------------------------

OPS = {
0x00:("BRK","imp"),0x01:("ORA","inx"),0x04:("TSB","zp"),0x05:("ORA","zp"),0x06:("ASL","zp"),0x07:("RMB0","zp"),
0x08:("PHP","imp"),0x09:("ORA","imm"),0x0A:("ASL","acc"),0x0C:("TSB","abs"),0x0D:("ORA","abs"),0x0E:("ASL","abs"),0x0F:("BBR0","zprel"),
0x10:("BPL","rel"),0x11:("ORA","iny"),0x12:("ORA","zpi"),0x14:("TRB","zp"),0x15:("ORA","zpx"),0x16:("ASL","zpx"),0x17:("RMB1","zp"),
0x18:("CLC","imp"),0x19:("ORA","absy"),0x1A:("INC","acc"),0x1C:("TRB","abs"),0x1D:("ORA","absx"),0x1E:("ASL","absx"),0x1F:("BBR1","zprel"),
0x20:("JSR","abs"),0x21:("AND","inx"),0x24:("BIT","zp"),0x25:("AND","zp"),0x26:("ROL","zp"),0x27:("RMB2","zp"),
0x28:("PLP","imp"),0x29:("AND","imm"),0x2A:("ROL","acc"),0x2C:("BIT","abs"),0x2D:("AND","abs"),0x2E:("ROL","abs"),0x2F:("BBR2","zprel"),
0x30:("BMI","rel"),0x31:("AND","iny"),0x32:("AND","zpi"),0x34:("BIT","zpx"),0x35:("AND","zpx"),0x36:("ROL","zpx"),0x37:("RMB3","zp"),
0x38:("SEC","imp"),0x39:("AND","absy"),0x3A:("DEC","acc"),0x3C:("BIT","absx"),0x3D:("AND","absx"),0x3E:("ROL","absx"),0x3F:("BBR3","zprel"),
0x40:("RTI","imp"),0x41:("EOR","inx"),0x45:("EOR","zp"),0x46:("LSR","zp"),0x47:("RMB4","zp"),
0x48:("PHA","imp"),0x49:("EOR","imm"),0x4A:("LSR","acc"),0x4C:("JMP","abs"),0x4D:("EOR","abs"),0x4E:("LSR","abs"),0x4F:("BBR4","zprel"),
0x50:("BVC","rel"),0x51:("EOR","iny"),0x52:("EOR","zpi"),0x55:("EOR","zpx"),0x56:("LSR","zpx"),0x57:("RMB5","zp"),
0x58:("CLI","imp"),0x59:("EOR","absy"),0x5A:("PHY","imp"),0x5D:("EOR","absx"),0x5E:("LSR","absx"),0x5F:("BBR5","zprel"),
0x60:("RTS","imp"),0x61:("ADC","inx"),0x64:("STZ","zp"),0x65:("ADC","zp"),0x66:("ROR","zp"),0x67:("RMB6","zp"),
0x68:("PLA","imp"),0x69:("ADC","imm"),0x6A:("ROR","acc"),0x6C:("JMP","ind"),0x6D:("ADC","abs"),0x6E:("ROR","abs"),0x6F:("BBR6","zprel"),
0x70:("BVS","rel"),0x71:("ADC","iny"),0x72:("ADC","zpi"),0x74:("STZ","zpx"),0x75:("ADC","zpx"),0x76:("ROR","zpx"),0x77:("RMB7","zp"),
0x78:("SEI","imp"),0x79:("ADC","absy"),0x7A:("PLY","imp"),0x7C:("JMP","abxi"),0x7D:("ADC","absx"),0x7E:("ROR","absx"),0x7F:("BBR7","zprel"),
0x80:("BRA","rel"),0x81:("STA","inx"),0x84:("STY","zp"),0x85:("STA","zp"),0x86:("STX","zp"),0x87:("SMB0","zp"),
0x88:("DEY","imp"),0x89:("BIT","imm"),0x8A:("TXA","imp"),0x8C:("STY","abs"),0x8D:("STA","abs"),0x8E:("STX","abs"),0x8F:("BBS0","zprel"),
0x90:("BCC","rel"),0x91:("STA","iny"),0x92:("STA","zpi"),0x94:("STY","zpx"),0x95:("STA","zpx"),0x96:("STX","zpy"),0x97:("SMB1","zp"),
0x98:("TYA","imp"),0x99:("STA","absy"),0x9A:("TXS","imp"),0x9C:("STZ","abs"),0x9D:("STA","absx"),0x9E:("STZ","absx"),0x9F:("BBS1","zprel"),
0xA0:("LDY","imm"),0xA1:("LDA","inx"),0xA2:("LDX","imm"),0xA4:("LDY","zp"),0xA5:("LDA","zp"),0xA6:("LDX","zp"),0xA7:("SMB2","zp"),
0xA8:("TAY","imp"),0xA9:("LDA","imm"),0xAA:("TAX","imp"),0xAC:("LDY","abs"),0xAD:("LDA","abs"),0xAE:("LDX","abs"),0xAF:("BBS2","zprel"),
0xB0:("BCS","rel"),0xB1:("LDA","iny"),0xB2:("LDA","zpi"),0xB4:("LDY","zpx"),0xB5:("LDA","zpx"),0xB6:("LDX","zpy"),0xB7:("SMB3","zp"),
0xB8:("CLV","imp"),0xB9:("LDA","absy"),0xBA:("TSX","imp"),0xBC:("LDY","absx"),0xBD:("LDA","absx"),0xBE:("LDX","absy"),0xBF:("BBS3","zprel"),
0xC0:("CPY","imm"),0xC1:("CMP","inx"),0xC4:("CPY","zp"),0xC5:("CMP","zp"),0xC6:("DEC","zp"),0xC7:("SMB4","zp"),
0xC8:("INY","imp"),0xC9:("CMP","imm"),0xCA:("DEX","imp"),0xCB:("WAI","imp"),0xCC:("CPY","abs"),0xCD:("CMP","abs"),0xCE:("DEC","abs"),0xCF:("BBS4","zprel"),
0xD0:("BNE","rel"),0xD1:("CMP","iny"),0xD2:("CMP","zpi"),0xD5:("CMP","zpx"),0xD6:("DEC","zpx"),0xD7:("SMB5","zp"),
0xD8:("CLD","imp"),0xD9:("CMP","absy"),0xDA:("PHX","imp"),0xDB:("STP","imp"),0xDD:("CMP","absx"),0xDE:("DEC","absx"),0xDF:("BBS5","zprel"),
0xE0:("CPX","imm"),0xE1:("SBC","inx"),0xE4:("CPX","zp"),0xE5:("SBC","zp"),0xE6:("INC","zp"),0xE7:("SMB6","zp"),
0xE8:("INX","imp"),0xE9:("SBC","imm"),0xEA:("NOP","imp"),0xEB:("NOP","imp"),0xEC:("CPX","abs"),0xED:("SBC","abs"),0xEE:("INC","abs"),0xEF:("BBS6","zprel"),
0xF0:("BEQ","rel"),0xF1:("SBC","iny"),0xF2:("SBC","zpi"),0xF5:("SBC","zpx"),0xF6:("INC","zpx"),0xF7:("SMB7","zp"),
0xF8:("SED","imp"),0xF9:("SBC","absy"),0xFA:("PLX","imp"),0xFD:("SBC","absx"),0xFE:("INC","absx"),0xFF:("BBS7","zprel")
}

with open(romfile, "rb") as f:
    rom = f.read()

pc = base
i = 0

while i < len(rom):
    if pc in labels:
        print(f"\n{labels[pc]}:")
    elif pc in auto_labels:
        print(f"\n{auto_labels[pc]}:")

    op = rom[i]

    if op not in OPS:
        print(f"{pc:04X}  {op:02X}       .byte ${op:02X}")
        pc += 1
        i += 1
        continue

    mnem, mode = OPS[op]

    if mode in ("imp", "acc"):
        size = 1
    elif mode in ("imm", "zp", "zpx", "zpy", "rel", "inx", "iny", "zpi"):
        size = 2
    elif mode in ("abs", "absx", "absy", "ind", "abxi"):
        size = 3
    elif mode == "zprel":
        size = 3
    else:
        size = 1

    if i + size > len(rom):
        size = 1

    operand = ""

    if size == 2 and i + 1 < len(rom):
        v = rom[i + 1]

        if mode == "imm":
            operand = f"#${v:02X}"
        elif mode == "rel":
            dest = (pc + 2 + (v - 256 if v > 127 else v)) & 0xFFFF
            operand = labels.get(dest, auto_labels.setdefault(dest, f"L{dest:04X}"))
        elif mode == "zp":
            operand = f"${v:02X}"
        elif mode == "zpx":
            operand = f"${v:02X},X"
        elif mode == "zpy":
            operand = f"${v:02X},Y"
        elif mode == "inx":
            operand = f"(${v:02X},X)"
        elif mode == "iny":
            operand = f"(${v:02X}),Y"
        elif mode == "zpi":
            operand = f"(${v:02X})"

    elif size == 3 and i + 2 < len(rom):
        lo = rom[i + 1]
        hi = rom[i + 2]
        addr = (hi << 8) | lo

        if mode == "abs":
            if mnem in ("JSR", "JMP"):
                operand = labels.get(addr, auto_labels.setdefault(addr, f"L{addr:04X}"))
            else:
                operand = labels.get(addr, f"${addr:04X}")
        elif mode == "absx":
            operand = f"{labels[addr]},X" if addr in labels else f"${addr:04X},X"
        elif mode == "absy":
            operand = f"{labels[addr]},Y" if addr in labels else f"${addr:04X},Y"
        elif mode == "ind":
            operand = f"({labels[addr]})" if addr in labels else f"(${addr:04X})"
        elif mode == "abxi":
            operand = f"({labels[addr]},X)" if addr in labels else f"(${addr:04X},X)"
        elif mode == "zprel":
            zp = lo
            rel = hi
            dest = (pc + 3 + (rel - 256 if rel > 127 else rel)) & 0xFFFF
            target = labels.get(dest, auto_labels.setdefault(dest, f"L{dest:04X}"))
            operand = f"${zp:02X},{target}"

    bytestr = " ".join(f"{b:02X}" for b in rom[i:i + size])
    print(f"{pc:04X}  {bytestr:<8} {mnem} {operand}".rstrip())

    pc += size
    i += size
