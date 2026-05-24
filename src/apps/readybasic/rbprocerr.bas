10 rem readybasic proc/fun negative probes
20 rem run 100,200,...,1500 one case at a time
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
900 exec needi((1+2)
910 end
1000 exec needi((1+2)))
1010 end
1100 exec needs(left$("bad",2))
1110 end
1200 fadd(1.2,2.3,a%)
1210 end
1300 a=ids("bad")
1310 end
1400 a$=addi(1,2)
1410 end
1500 print addi(1,(2+4)
1510 end
1600 print addi(1,(2+4)))
1610 end
2000 proc needi(p%)
2010 endp
2100 proc needs(s$)
2110 endp
2200 func fni(p%)
2210 ret p%+1
2220 endp
2300 proc nop(p%)
2310 endp
2400 proc d1()
2410 exec d2
2420 endp
2500 proc d2()
2510 exec d3
2520 endp
2600 proc d3()
2610 exec d4
2620 endp
2700 proc d4()
2710 exec d5
2720 endp
2800 proc d5()
2810 endp
