10 print "procfunc"
20 exec show0
30 exec showi(7)
40 exec shows("yo")
50 exec addlate(4,5,a%)
60 print "sum";a%
70 exec greet("ready",a$)
80 print a$
90 print "chain":exec showi(8):print "after"
100 if 1 then :exec addi(1,2,a%)
110 print "if";a%
120 exec outer(3,a%)
130 print "nested";a%
140 print "efn";addi(6,7)
150 b=addi(2,3):print "efass";b
160 t$=greet("expr"):print t$
170 exec idi(9,a%):print "ret%";a%
180 t$=ids("ok"):print "ret$ ";t$
190 end
1000 proc show0()
1010 print "proc0"
1020 endp
1100 proc showi(p%)
1110 print "proci";p%
1120 endp
1200 proc shows(s$)
1210 print "procs ";s$
1220 endp
1300 func addi(x%,y%)
1310 ret x%+y%
1320 endp
1400 func greet(n$)
1410 ret "hi "+n$
1420 endp
1500 func inner(x%)
1510 ret x%+10
1520 endp
1600 func outer(x%)
1610 exec inner(x%,r%)
1620 r%=r%+1
1630 ret r%
1640 endp
1700 func addlate(x%,y%)
1710 r%=x%+y%
1720 ret r%
1730 endp
1800 func idi(x%)
1810 ret% x%
1820 endp
1900 func ids(s$)
1910 ret$ s$
1920 endp
