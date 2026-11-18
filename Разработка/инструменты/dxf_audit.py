#!/usr/bin/env python
# -*- coding: utf-8 -*-
r"""Проверка DXF, выгруженного из Airfoil Studio.

Смотрит то, из-за чего были проблемы в SolidWorks:
  * единицы в заголовке ($INSUNITS = 4 — миллиметры, $MEASUREMENT = 1 — метрика);
  * фактический габарит контура — должен совпасть с хордой в мм;
  * есть ли вообще контуры (LWPOLYLINE / POLYLINE).

Использование:
    python dxf_audit.py профиль.dxf            # только единицы и габарит
    python dxf_audit.py профиль.dxf 250        # сверить габарит с хордой 250 мм

Требуется ezdxf:  pip install ezdxf
"""
import sys

try:
    import ezdxf
except ImportError:
    print("нужен ezdxf:  pip install ezdxf")
    sys.exit(2)


def collect_points(doc):
    pts = []
    for e in doc.modelspace():
        t = e.dxftype()
        if t == "LWPOLYLINE":
            pts += [(float(p[0]), float(p[1])) for p in e.get_points("xy")]
        elif t == "POLYLINE":
            pts += [(float(v.dxf.location.x), float(v.dxf.location.y)) for v in e.vertices]
        elif t == "LINE":
            pts += [(float(e.dxf.start.x), float(e.dxf.start.y)),
                    (float(e.dxf.end.x), float(e.dxf.end.y))]
    return pts


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2

    path = argv[1]
    doc = ezdxf.readfile(path)
    hdr = doc.header
    insunits = hdr.get("$INSUNITS", None)
    measure = hdr.get("$MEASUREMENT", None)

    print("файл:", path)
    print("$INSUNITS    =", insunits, "(4 = миллиметры)")
    print("$MEASUREMENT =", measure, "(1 = метрическая система)")

    pts = collect_points(doc)
    if not pts:
        print("контуров не найдено — проверьте DXF")
        return 1

    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    w = max(xs) - min(xs)
    h = max(ys) - min(ys)
    print("габарит контура: %.3f x %.3f" % (w, h))

    ok_size = True
    if len(argv) > 2:
        want = float(argv[2])
        ok_size = abs(w - want) < 0.5
        print("ожидаемая хорда: %.3f мм -> %s" % (want, "совпадает" if ok_size else "НЕ совпадает, проверить масштаб"))

    ok_units = (insunits == 4) and (measure == 1)
    print("единицы: %s" % ("миллиметры — ок" if ok_units else "НЕ миллиметры"))

    if not (ok_units and ok_size):
        print("ИТОГ: есть замечания (см. выше)")
        return 1
    print("ИТОГ: всё в порядке")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
