;
; ADTPro - Apple Disk Transfer ProDOS
; Copyright (C) 2012 by David Schmidt
; david__schmidt at users.sourceforge.net
;
; This program is free software; you can redistribute it and/or modify it 
; under the terms of the GNU General Public License as published by the 
; Free Software Foundation; either version 2 of the License, or (at your 
; option) any later version.
;
; This program is distributed in the hope that it will be useful, but 
; WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY 
; or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License 
; for more details.
;
; You should have received a copy of the GNU General Public License along 
; with this program; if not, write to the Free Software Foundation, Inc., 
; 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
;
; Virtual disk drive based on ideas from Terence J. Boldt

; PRODOS ZERO PAGE VALUES
COMMAND	= $42 ; PRODOS COMMAND
UNIT	= $43 ; PRODOS SLOT/DRIVE
BUFLO	= $44 ; LOW BUFFER
BUFHI	= $45 ; HI BUFFER
BLKLO	= $46 ; LOW BLOCK
BLKHI	= $47 ; HI BLOCK

; PRODOS ERROR CODES
IOERR	= $27
NODEV	= $28
WPERR	= $2B

; Activity screen location
SCRN_THROB	= $0427

; DRIVER CODE
DRIVER:
	cld
; CHECK THAT WE HAVE THE RIGHT DRIVE
	lda	UNIT
	cmp	#$20 ; SLOT 2 DRIVE 1
	beq	DOCMD ; YEP, DO COMMAND
	sec	; NOPE, FAIL
	lda	#NODEV
	rts

; CHECK WHICH COMMAND IS REQUESTED
DOCMD:
	lda	COMMAND
	bne	NOTSTAT ; 0 IS STATUS
	jmp	GETSTAT
NOTSTAT:
	cmp	#$01
	bne	NOREAD ; 1 IS READ
	jmp	READBLK
NOREAD:
	cmp	#$02
	bne	@NOWRITE ; 2 IS WRITE
	jmp	WRITEBLK
@NOWRITE:
	lda	#$00 ; CLEAR ERROR
	clc
	rts

; STATUS
GETSTAT:
	lda	#$00
	ldx	#$FF
	ldy	#$FF
	clc
	rts

CALC_CHECKSUM:			; Calculate the checksum of the block at BLKLO/BLKHI
	lda	#$00		; Clean everyone out
	tax
	tay
CC_LOOP:
	eor	(BUFLO),Y	; Exclusive-or accumulator with what's at (BUFLO),Y
	sta	CHECKSUM	; Save that tally in CHECKSUM as we go
	iny
	bne	CC_LOOP
	inc	BUFHI		; Y just turned over to zero; bump MSB of buffer
	inx			; Keep track of trips through the loop - we need two of them
	cpx	#$02		; The second time X is incremented, this will signfiy twice through the loop
	bne	CC_LOOP

	dec	BUFHI		; BUFHI got bumped twice, so back it back down
	dec	BUFHI
	rts

;---------------------------------------------------------
; abort - stop everything
;---------------------------------------------------------
PABORT:
	sec
	rts		; Not implemented

;---------------------------------------------------------
; Variables
;---------------------------------------------------------
SCREEN_CONTENTS:
	.byte	$00	; Storage for the character on screen when throbbing
CHECKSUM:
	.byte	$00