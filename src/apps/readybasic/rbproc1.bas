10 print "procfunc"
20 exec show0
30 exec showi,7
40 exec shows,"yo"
50 exec addi,4,5,a%
60 print "sum";a%
70 exec greet,"ready",a$
80 print a$
90 print "chain":exec showi,8:print "after"
100 if 1 then :exec addi,1,2,a%
110 print "if";a%
120 exec outer,3,a%
130 print "nested";a%
140 end
1000 proc show0
1010 print "proc0"
1020 endp
1100 proc showi p%
1110 print "proci";p%
1120 endp
1200 proc shows s$
1210 print "procs ";s$
1220 endp
1300 func addi x%,y%,r%
1310 r%=x%+y%
1320 endp
1400 func greet n$,r$
1410 r$="hi "+n$
1420 endp
1500 func inner x%,r%
1510 r%=x%+10
1520 endp
1600 func outer x%,r%
1610 exec inner,x%,r%
1620 r%=r%+1
1630 endp
