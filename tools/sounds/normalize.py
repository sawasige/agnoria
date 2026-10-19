# -*- coding: utf-8 -*-
"""render-fanfare.swift が書き出した WAV（32bit float ステレオ）をピーク -6 dBFS に正規化し、末尾の無音を詰めて 16bit WAV にする。
使い方: python3 tools/sounds/normalize.py in.wav out.wav && afconvert -f caff -d LEI16 out.wav Agnoria/Resources/Sounds/fanfare.caf
"""
import sys, struct, array, wave

def read_float_wav(path):
    b = open(path, 'rb').read()
    pos = 12
    fmt = None
    while pos + 8 <= len(b):
        cid = b[pos:pos+4]; size = struct.unpack('<I', b[pos+4:pos+8])[0]; pos += 8
        if cid == b'fmt ':
            fmt = struct.unpack('<HHIIHH', b[pos:pos+16])
        elif cid == b'data':
            a = array.array('f'); a.frombytes(b[pos:pos+size]); return fmt, a
        pos += size + (size & 1)
    raise SystemExit('data chunk not found')

fmt, a = read_float_wav(sys.argv[1])
channels, rate = fmt[1], fmt[2]
peak = max(abs(x) for x in a) or 1.0
gain = 0.5 / peak
last = len(a)
while last > 0 and abs(a[last-1]) < 0.001: last -= 1
last = min(len(a), last + rate * channels // 5)
out = array.array('h', [int(max(-32767, min(32767, x * gain * 32767))) for x in a[:last]])
w = wave.open(sys.argv[2], 'w'); w.setnchannels(channels); w.setsampwidth(2); w.setframerate(rate); w.writeframes(out.tobytes()); w.close()
print('peak gain x%.1f, %.2f s' % (gain, len(out) / channels / rate))
