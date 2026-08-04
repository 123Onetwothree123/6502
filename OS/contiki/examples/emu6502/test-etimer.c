#include "contiki.h"
#include <stdio.h>

PROCESS(timer_proc, "Timer test");
AUTOSTART_PROCESSES(&timer_proc);

PROCESS_THREAD(timer_proc, ev, data)
{
  static struct etimer t;
  PROCESS_BEGIN();

  printf("Contiki etimer up");

  while(1) {
    etimer_set(&t, CLOCK_SECOND * 2);
    PROCESS_WAIT_EVENT_UNTIL(etimer_expired(&t));
    printf("tick");
  }

  PROCESS_END();
}
