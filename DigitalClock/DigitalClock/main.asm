;
; DigitalClock.asm
;
; 
;Author: Paulo Roberto / Rita de Kassia / Vinicius Rafael



;Definições de clock
#define CLOCK 16.0e6 ;clock speed
#define DELAY 0.01 ;seconds
.equ PRESCALE = 0b100 ;/256 prescale
.equ PRESCALE_DIV = 256
.equ WGM = 0b0100
.equ TOP = int(0.5 + ((CLOCK/PRESCALE_DIV)*DELAY))
.if TOP > 65535
.error "TOP is out of range"
.endif
;
; Created: 10/04/2025 18:13:31
; Author : rita / paulo
;

STATE_TABLE:
    .dw state0_operation ,state1_operation ,state2_operation
	.dw state3_operation ,state4_operation ,state5_operation 
	.dw state6_operation  ,state7_operation 


.def current_state = r16
.def temp = r17
.def stack_reg = r18

.equ state0 = 0   ; MODO 1 – Relógio (contagem normal de tempo MM:SS)
.equ state1 = 1   ; MODO 2 – PRE 2 (cronômetro parado, resetado)
.equ state2 = 2   ; MODO 2 – CRON RUN (cronômetro em contagem)
.equ state3 = 3   ; MODO 2 – CRON STOP (cronômetro pausado)
.equ state4 = 4   ; MODO 3 – PRE 3 (pré-ajuste de hora, entrada no modo de ajuste)
.equ state5 = 5   ; MODO 3 – BLINK (pisca o dígito selecionado)
.equ state6 = 6   ; MODO 3 – MOV SELECT (muda qual dígito está sendo ajustado)
.equ state7 = 7   ; MODO 3 – SELECT INC (incrementa o dígito selecionado)


reset:
	;Inicialização de stack
	ldi stack_reg, low(RAMEND)
	out SPL, stack_reg
	ldi stack_reg, high(RAMEND)
	out SPH, stack_reg
	;Definindo o estado atual para o primeiro estado na tabela
	ldi current_state, 0
	out DDRB, current_state

	;Inicializações de timer
	ldi stack_reg, high(TOP) ;initialize compare value (TOP)
	sts OCR1AH, stack_reg
	ldi stack_reg, low(TOP)
	sts OCR1AL, stack_reg
	ldi stack_reg, ((WGM&0b11) << WGM10) ;lower 2 bits of WGM
	; WGM&0b11 = 0b0100 & 0b0011 = 0b0000 
	sts TCCR1A, stack_reg
	;upper 2 bits of WGM and clock select
	ldi stack_reg, ((WGM>> 2) << WGM12)|(PRESCALE << CS10)
	; WGM >> 2 = 0b0100 >> 2 = 0b0001
	; (WGM >> 2) << WGM12 = (0b0001 << 3) = 0b0001000
	; (PRESCALE << CS10) = 0b100 << 0 = 0b100
	; 0b0001000 | 0b100 = 0b0001100

	sts TCCR1B, stack_reg ;start counter

	sei
	call transition ;Pula direto para o estado de transição

main:
	in stack_reg, TIFR1 ;request status from timers
	andi stack_reg, 1<<OCF1A ;isolate only timer 1's match
	; 0b1 << OCF1A = 0b1 << 1 = 0b00000010
	; andi --> 1 (OCF1A é um)	--> overflow
	; andi --> 0 (OCF1A é zero)	--> contando
	breq skipoverflow ;skip overflow handler
	;match handler - done once every DELAY seconds
	ldi stack_reg, 1<<OCF1A ;write a 1 to clear the flag
	out TIFR1, stack_reg
	rjmp main


overflow:
	nop
	rjmp main
irq:
	push temp
	in temp, sreg
	push temp
	; pegar o valor de pc para somar o valor do estado atual e fazer a transição
	call current_pc 
	current_pc:
		pop ZH
		pop ZL
	ldi temp, 10
	lsl current_state ; garante que vai pular +1 instrução (rjmp exit_irq)
	add temp, current_state 
	lsr current_state ; retorna o valor original de current_state 
	add ZL, temp
	clr temp
	adc ZH, temp
	; pula pro valor de PC + o estado atual
	ijmp
	case_state0: ldi current_state, state1
		rjmp exit_irq
	case_state1: ldi current_state, state4
		rjmp exit_irq
	case_state2: ldi current_state, state4
		rjmp exit_irq
	case_state3: ldi current_state, state4
		rjmp exit_irq
	case_state4: ldi current_state, state0
		rjmp exit_irq
	case_state5: ldi current_state, state0
		rjmp exit_irq
	case_state6: ldi current_state, state0
		rjmp exit_irq
	case_state7: ldi current_state, state0
		rjmp exit_irq

	exit_irq:
		pop temp
		out sreg, temp
		pop temp
		reti

; interrupção para quando apertar "START"
irq_start:
	push temp
	in temp, sreg
	push temp
	; pegar o valor de pc para somar o valor do estado atual e fazer a transição
	call current_pc_start
	current_pc_start:
		pop ZH
		pop ZL
	ldi temp, 10
	lsl current_state ; garante que vai pular +1 instrução (rjmp exit_irq)
	add temp, current_state 
	lsr current_state ; retorna o valor original de current_state 
	add ZL, temp
	clr temp
	adc ZH, temp
	; pula pro valor de PC + o estado atual
	ijmp
	case_state0_start: ldi current_state, state0
		rjmp exit_irq_start
	case_state1_start: ldi current_state, state2
		rjmp exit_irq_start
	case_state2_start: ldi current_state, state3
		rjmp exit_irq_start
	case_state3_start: ldi current_state, state2
		rjmp exit_irq_start
	case_state4_start: ldi current_state, state4
		rjmp exit_irq_start
	case_state5_start: ldi current_state, state6
		rjmp exit_irq_start
	case_state6_start: ldi current_state, state6
		rjmp exit_irq_start
	case_state7_start: ldi current_state, state7
		rjmp exit_irq_start

	exit_irq_start:
		pop temp
		out sreg, temp
		pop temp
		reti

; interrupção para quando apertar "RESET"
irq_reset:
    push temp
    in temp, sreg
    push temp

    call current_pc_reset
current_pc_reset:
    pop ZH
    pop ZL
    ldi temp, 10               
    lsl current_state          
    add temp, current_state
    lsr current_state          
    add ZL, temp
    clr temp
    adc ZH, temp
    ijmp

	; transições ao apertar RESET
	case_reset_state0: ldi current_state, state0 ; MODO 1, não faz nada
		rjmp exit_irq_reset
	case_reset_state1: ldi current_state, state1 ; PRE 2, não faz nada
		rjmp exit_irq_reset
	case_reset_state2: ldi current_state, state2 ; CRON RUN, não faz nada
		rjmp exit_irq_reset
	case_reset_state3: ldi current_state, state1; CRON STOP, volta pra PRE 2
		rjmp exit_irq_reset
	case_reset_state4: ldi current_state, state4 ; PRE 3, não faz nada
		rjmp exit_irq_reset
	case_reset_state5: ldi current_state, state7 ; BLINK vai pra SELECT INC
		rjmp exit_irq_reset
	case_reset_state6: ldi current_state, state6 ; MOV SELECT, não faz nada
		rjmp exit_irq_reset
	case_reset_state7: ldi current_state, state7 ; SELECT INC, não faz nada (transição automática)
		rjmp exit_irq_reset

	exit_irq_reset:
		pop temp
		out sreg, temp
		pop temp
		reti

transition:
	ldi ZL, LOW(STATE_TABLE<<1)
	ldi ZH, HIGH(STATE_TABLE<<1)
	lsl current_state
	add ZL, current_state
	lsr current_state
	clr temp
	adc ZH, temp
	lpm R0, Z+
	lpm R1, Z	
	movw ZL, R0
	ijmp

state0_operation:
    cpi current_state, state0
    brne transition ; se NÃO for o estado 0, pula pra transition

	; lógica

    rjmp state0_operation

state1_operation:
    cpi current_state, state1
    brne transition 

	; lógica

    rjmp state1_operation

state2_operation:
    cpi current_state, state2
    brne transition 

	; lógica

    rjmp state2_operation

state3_operation:
    cpi current_state, state3
    brne transition 

	; lógica

    rjmp state3_operation

state4_operation:
    ; desabilita interrupções
    cli
    
    ; logica

    ldi current_state, state5
    sei
    rjmp main

state5_operation:
    cpi current_state, state5
    brne transition 

	; lógica

    rjmp state5_operation

state6_operation:
    ; desabilita interrupções
    cli
    
    ; logica

    ldi current_state, state5
    sei
    rjmp main

state7_operation:
    ; desabilita interrupções
    cli
    
    ; logica

    ldi current_state, state5
    sei
    rjmp main

