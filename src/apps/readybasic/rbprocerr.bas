10 rem readybasic proc/fun negative probes
20 rem run 100,200,...,800 one case at a time
100 exec missing(1)
110 end
200 exec needi()
210 end
300 exec needi("bad")
310 end
400 exec needs(7)
410 end
500 exec fni(7)
510 end
600 exec nop(1,a%)
610 end
700 endp
710 end
800 exec d1
810 end
1000 proc needi(p%)
1010 endp
1100 proc needs(s$)
1110 endp
1200 func fni(p%)
1210 ret p%+1
1220 endp
1300 proc nop(p%)
1310 endp
1400 proc d1()
1410 exec d2
1420 endp
1500 proc d2()
1510 exec d3
1520 endp
1600 proc d3()
1610 exec d4
1620 endp
1700 proc d4()
1710 exec d5
1720 endp
1800 proc d5()
1810 endp
