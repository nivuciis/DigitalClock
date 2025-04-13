;
; DigitalClock.asm
;
; 
;Authors: Paulo Roberto / Rita de Kassia / Vinicius Rafael



;Definições de clock
.equ DISPLAY_DELAY = 5 ; ms
.equ TIMER_PRESCALE = 64 
.equ TIMER_COMPARE = (16000000/64/1000)*DISPLAY_DELAY ; Valor para comparar
.dseg 
.org SRAM_START
current_digit: .byte 1
hora_dezena: .byte 1
hora_unidade: .byte 1
minuto_dezena: .byte 1
minuto_unidade: .byte 1
display_atual: .byte 1
contador_timer: .byte 2

.cseg
.org 0x0000
		rjmp reset
.org OVF1addr
	rjmp TIMER1_OVF_ISR

STATE_TABLE: ;Armazena o local em que os estados estão alocados
    .dw  TEMPO_INC, PRE_TWO ,CRON_RUN
	.dw CRON_STOP , PRE_THREE ,BLINK
	.dw MOV_SELECT  ,SELECT_INC

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
	ldi current_state, state0
	ser temp
	out DDRD, temp ; seta a porta C como saida dos displays
	ldi temp, 0x0F ;seta os 4 primeiros pinos da porta B como saida de controle 
	out DDRB, temp
	
	;Inicialização das variaveis
	ldi temp, 1
	sts hora_dezena, temp
	ldi temp, 3
	sts hora_unidade, temp
	sts minuto_dezena, temp
	clr temp
	sts minuto_unidade, temp
	sts display_atual, temp
	sts contador_timer, temp
	sts contador_timer+1, temp

	; Configurar timer 1 para interrupção por overflow 

	sei ; Habilitar interrupções
	call transition ;Pula direto para o estado de transição

main:
	rjmp main

setup_timer:
    ldi temp, high(TIMER_COMPARE)
	sts OCR1AH, temp
	ldi temp, low(TIMER_COMPARE)
	sts OCR1AL, temp

	ldi temp, (1<<WGM12)| (1<<CS11)|(1<<CS10) ; AJuste do ctc para um prescale de 64
	sts TCCR1B, temp
	ldi temp, (1<<OCIE1A) ; interrupcao por comparacao
	sts TIMSK1, temp
	ret


; --- Timer1 interrupt handler ---
TIMER1_OVF_ISR:
    push temp
    push stack_reg
	push mosfet
	in temp, sreg
	push temp

	lds temp, display_atual

	lds stack_reg, 0x0F
	out PORTB, stack_reg

	cpi temp, 0
	breq mostrar_hora_dezena
	cpi temp, 1
	breq mostrar_hora_unidade
	cpi temp, 2
	breq mostrar_minuto_dezena
	cpi temp, 3
	breq mostrar_minuto_unidade

	mostrar_hora_dezena:
		lds stack_reg, hora_dezena
		rjmp show_digits
	mostrar_hora_unidade:
		lds stack_reg, hora_unidade
		rjmp show_digits
	mostrar_minuto_dezena:
		lds stack_reg, minuto_dezena
		rjmp show_digits
	mostrar_minuto_unidade:
		lds stack_reg, minuto_unidade
		
	show_digits:
		ldi ZL, low(DIGITS_TABLE<<1)
		ldi ZH, high(DIGITS_TABLE<<1)
		add ZL, stack_reg
		lpm temp, Z

		out PORTD, temp

		ldi stack_reg, 0x0F
		com temp
		and stack_reg, temp
		out PORTB, stack_reg

		lds temp, display_atual
		inc temp
		cpi temp, 4
		brne save_actual_display
		ldi temp, 0
		save_actual_display:
			sts display_atual, temp

		lds temp, contador_timer
		lds stack_reg, contador_timer+1
		inc stack_reg
		inc temp
		cpi temp, low(200)
		ldi mosfet, high(200)
		cpc stack_reg, mosfet
		brne end_timerISR
		clr temp
		clr stack_reg
		clr mosfet
		rcall atualiza_tempo
		end_timerISR:
			sts contador_timer, temp
			sts contador_timer+1, stack_reg
			pop temp
			out sreg, temp
			pop mosfet
			pop stack_reg
			pop temp
			reti

atualiza_tempo:
	push temp
	push stack_reg

	lds temp, minuto_unidade
	inc temp
	cpi temp, 10
	brne salva_minuto_unidade
	clr temp
	lds stack_reg, minuto_dezena
	inc stack_reg
	cpi stack_reg, 6
	brne salva_minuto_dezena

	clr stack_reg
	lds temp, hora_unidade
	inc temp
	cpi temp, 10
	brne salva_hora_unidade

	clr temp
	lds stack_reg, hora_dezena
	inc stack_reg
	cpi stack_reg, 3
	brne salva_hora_dezena

	clr temp
	clr stack_reg
	sts hora_dezena, temp
	sts hora_unidade, temp
	rjmp fim_atualizacao
			
	salva_hora_dezena:
		sts hora_dezena, stack_reg
		rjmp fim_atualizacao
	salva_hora_unidade:
		sts hora_unidade, temp
		rjmp fim_atualizacao
	salva_minuto_dezena:
		sts minuto_dezena, stack_reg
		rjmp salva_minuto_unidade
	salva_minuto_unidade:
		sts minuto_unidade, temp
	fim_atualizacao:
		pop stack_reg
		pop temp
		ret

MODE_ISR:
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
START_ISR:
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
RESET_ISR:
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



;---------------------MODO 1 RELOGIO-----------------------------
TEMPO_INC:
    cpi current_state, state0
    brne transition ; se NÃO for o estado 0, pula pra transition
	call setup_timer
	call tempo_inc_loop
	tempo_inc_loop:
		nop
		rjmp tempo_inc_loop
	
	rjmp TEMPO_INC


;------------------------------MODO 2 CRONOMETRO ZERADO---------------------
PRE_TWO:
    cpi current_state, state1
    brne transition 

	; lógica

    rjmp PRE_TWO
	

;------------------------------MODO 2 CRONOMETRO RODANDO--------------------------
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

;---------------------------------------MODO 2 CRONOMETRO PARADO--------------------------
CRON_STOP:
    cpi current_state, state3
    brne transition 

	; lógica

    rjmp CRON_STOP


;------------------------- MODO 3 APENAS BIP------------------------------------
PRE_THREE:
    ; desabilita interrupções
    cli
    
    ; logica

    ldi current_state, state5
    sei
    rjmp main

;-----------------------------------MODO 3 DISPLAY SELECIONADO PISCANDO----------------------------
BLINK:
    cpi current_state, state5
    brne transition 

	; lógica

    rjmp BLINK


;------------------------------------------MODO 3 MUDA O DISPLAY QUE SERA SELECIONADO----------------------------
MOV_SELECT:
    ; desabilita interrupções
    cli
    
    ; logica

    ldi current_state, state5
    sei
    rjmp main

;----------------------------------------------- MODO 3 MUDA O VALOR NO DISPLAY SELECIONADO-------------------------------
SELECT_INC:
    ; desabilita interrupções
    cli
    
    ; logica

    ldi current_state, state5
    sei
    rjmp main


;----------------------------------- FUNC PARA INCREMENTAR TIMER --------------------------------------
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
	