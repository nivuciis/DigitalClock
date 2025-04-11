;
; DigitalClock.asm
;
; 
;


; Replace with your application code


STATE_TABLE : .dw INITIAL_STATE, PRE_TWO, CRON_STOP
.def current_state = r16
.def temp = r17
clr temp
LDI R16, 2
transition:
	ldi ZL, LOW(STATE_TABLE)
	ldi ZH, HIGH(STATE_TABLE)
	lsl current_state
	add ZL, current_state
	lsr current_state
	adc ZH, temp
	lpm R0, Z+
	lpm R1, Z
	movw ZL, R0
	ijmp


reset:
	rjmp main

INITIAL_STATE:



	rjmp INITIAL_STATE
PRE_TWO:

	rjmp PRE_TWO

CRON_RUN:

	rjmp CRON_RUN

CRON_STOP:

	rjmp CRON_STOP

BLINK:

	rjmp BLINK


main:
	RJMP MAIN
	