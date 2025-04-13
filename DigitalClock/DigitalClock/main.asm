;
; DigitalClock.asm
;
; 
;Authors: Paulo Roberto / Rita de Kassia / Vinicius Rafael



;Definições de clock
#define CLOCK 16.0e6 ;clock speed
#define DELAY 1 ;seconds
.equ PRESCALE = 0b100 ;/256 prescale
.equ PRESCALE_DIV = 256
.equ WGM = 0b0100
.equ TOP = int(0.5 + ((CLOCK/PRESCALE_DIV)*DELAY))
.if TOP > 65535
.error "TOP is out of range"
.endif

.dseg 
current_digit: .byte 1
HOUR: .byte 2
MINUTES: .byte 2
.cseg
.org 0x0000
		rjmp reset
.org 0x0016        ; Timer1 Compare A interrupt vector
    rjmp TIMER1_COMPA_ISR ; Timer dos segundos

STATE_TABLE: ;Armazena o local em que os estados estão alocados
    .dw state0_operation ,state1_operation ,CRON_RUN
	.dw state3_operation ,state4_operation ,state5_operation 
	.dw state6_operation  ,state7_operation 

DIGITS_TABLE: ;Armazena os caracteres 0-9 em forma binaria
	.db 0b00111111, 0b00000110  ; 0, 1
    .db 0b01011011, 0b01001111  ; 2, 3
    .db 0b01100110, 0b01101101  ; 4, 5
    .db 0b01111101, 0b00000111  ; 6, 7
    .db 0b01111111, 0b01101111  ; 8, 9

.def current_state = r16
.def temp = r17
.def stack_reg = r18
.def mosfet = r19
;Utilizamos isto aqui para comparar em qual estado se encontra o current_state

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
	ser temp
	out DDRC, temp ; seta a porta C como saida
	out DDRB, temp ; porta B também pra jogar nos mosfets
	clr temp 

	sei ; Habilitar interrupções
	call transition ;Pula direto para o estado de transição

main:
	rjmp main

setup_timer:
    ldi r16, (1 << WGM12) | (1 << CS12)  ; CTC mode, prescaler=256

    sts TCCR1B, r16
    ldi r16, high(TOP)                  ; Delay de 1s @ 16MHz
    sts OCR1AH, r16
    ldi r16, low(TOP)
    sts OCR1AL, r16	
    ldi r16, (1 << OCIE1A)               ; Habilita a interrupção do timer 1
    sts TIMSK1, r16
	ser mosfet
	out PORTB, mosfet
    ret


; --- Timer1 interrupt handler ---
TIMER1_COMPA_ISR:
    push r16
    lds r16, current_digit
    inc r16
    cpi r16, 10
    brlo save_digit
    clr r16                   ; Volta para o 0 depois de 9
	save_digit:
		sts current_digit, r16
		pop r16
		reti

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

;Sempre utilizar o sts current_digit, r16 para pegar o valor do digito atual
update_display:
	ldi ZL, low(DIGITS_TABLE << 1)  
    ldi ZH, high(DIGITS_TABLE << 1)
    lds r16, current_digit
    add ZL, r16                  ; Add offset 
    clr r17
    adc ZH, r17                  
    lpm r16, Z                   
    out PORTC, r16               ; Envia para o display
    ret


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
	rjmp state0_operation

state1_operation:
    cpi current_state, state1
    brne transition 

	; lógica

    rjmp state1_operation

CRON_RUN:
    cpi current_state, state2
    brne transition 
	call setup_timer;Faz as definições de timer
	; lógica

    rjmp cron_run_timer_loop
	

	cron_run_timer_loop:
		rcall update_display
		rjmp cron_run_timer_loop

	; lógica

    rjmp CRON_RUN

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

inc_timer:
	push temp
	in temp, sreg
	push temp
	; pegar o valor de pc para somar o valor do estado atual e fazer a transição
	call current_pc_timer
	current_pc_timer:
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
	