*
* ADTPro - Apple Disk Transfer ProDOS
* Copyright (C) 2006 by David Schmidt
* david__schmidt at users.sourceforge.net
*
* This program is free software; you can redistribute it and/or modify it 
* under the terms of the GNU General Public License as published by the 
* Free Software Foundation; either version 2 of the License, or (at your 
* option) any later version.
*
* This program is distributed in the hope that it will be useful, but 
* WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY 
* or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License 
* for more details.
*
* You should have received a copy of the GNU General Public License along 
* with this program; if not, write to the Free Software Foundation, Inc., 
* 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
*

*---------------------------------------------------------
* SEND/RECEIVE functions
*
* Assumes a volume has been chosen via PICKVOL, setting:
*   UNITNBR
*   NUMBLKS
*   NUMBLKS+1
*---------------------------------------------------------

*---------------------------------------------------------
* SEND
*---------------------------------------------------------
SEND
	jsr GETFN
	bne SM.START
	jmp SM.DONE
	* Validate the filename won't overwite
SM.START


	jsr PICKVOL
*			Accumulator now has the index into device table
	bmi SM.DONE1
	sta SLOWA

	lda UNITNBR	Set up the unit number
	sta PARMBUF+1

	ldy #PMWAIT
	jsr SHOWM1	Tell user to have patience

	lda #CHR_P	Tell host we are Putting/Sending
	jsr PUTC

	jsr SENDFN	Send file name

	lda NUMBLKS	Send the total block size
	jsr PUTC
	lda NUMBLKS+1
	jsr PUTC

	jsr GETC	Get response from host
	beq PCOK
	jmp PCERROR

SM.DONE1
	rts

PCOK
	* Here's where we set up a loop
	* for all blocks to transfer.
	jsr PREPPRG	Prepare the progress screen
	lda #CHR_ACK
	jsr PUTC
	lda #$00
	sta CURBLK
	sta CURBLK+1

SM.MORE
	lda NUMBLKS
	sec
	sbc CURBLK
	sta DIFF
	lda NUMBLKS+1
	sbc CURBLK+1
	sta DIFF+1
	bne SM.FULL
	lda DIFF
	cmp #$28
	bcs SM.FULL
	tay
	jmp SM.PARTIAL

SM.FULL
	ldy #$28
	sty DIFF
SM.PARTIAL
	lda CURBLK
	sta BLKLO
	lda CURBLK+1
	sta BLKHI
	jsr READING
	lda CURBLK
	sta BLKLO
	lda CURBLK+1
	sta BLKHI
	ldy DIFF	
	jsr SENDING

	lda BLKLO
	sta CURBLK
	lda BLKHI
	sta CURBLK+1

	* Now, need to see if we're over the size limit...

	cmp NUMBLKS+1	Compare high-order num blocks byte
	bcc SM.MORE
	lda BLKLO
	cmp NUMBLKS	Compare low-order num blocks byte
	bcc SM.MORE

	lda #$00	TODO: This should count errors...
	jsr PUTC	SEND ERROR FLAG TO PC

	jsr COMPLETE
SM.DONE	rts

PCERROR
	pha
	ldy #PMSG13
	jsr SHOWM1
	pla
	tay
	jsr SHOWHMSG
	jsr PAUSE
	jmp BABORT


*---------------------------------------------------------
* RECEIVE
*---------------------------------------------------------
RECEIVE	
	jsr GETFN
	bne SR.START
	jmp SR.DONE

SR.START
	ldy #PMWAIT
	jsr SHOWM1	Tell user to have patience

*			Validate the filename exists
	lda #CHR_Z	Ask host for file size
	jsr PUTC

	jsr SENDFN	Send file name

	jsr GETC	Get response from host: file size
	sta HOSTBLX
	jsr GETC
	sta HOSTBLX+1
	jsr GETC	Get response from host: return code/message
	beq SR.OK
	jmp PCERROR

SR.OK
	jsr PICKVOL
*			Accumulator now has the index into device table
* 			Validate size matches volume picked
	bmi SM.DONE	Branch backwards... we just need an RTS close by
	sta SLOWA	Hang on to the device table index

	lda HOSTBLX
	cmp NUMBLKS
	bne SR.MISMATCH
	lda HOSTBLX+1
	cmp NUMBLKS+1
	bne SR.MISMATCH
	jmp SR.OK2
SR.MISMATCH
	ldy #PMSG35
	jsr SHOWM1
	jmp COMPLETE.1

SR.OK2
	lda UNITNBR
	sta PARMBUF+1

	lda #CHR_G	Tell host we are Getting/Receiving
	jsr PUTC
	jsr SENDFN	Send file name
	jsr GETC	Get response from host: return code/message
	beq SR.OK3
	jmp PCERROR

	* Here's where we set up a loop
	* for all blocks to transfer.
SR.OK3
	ldx SLOWA
	jsr PREPPRG
	lda #$00
	sta CURBLK
	sta CURBLK+1

SR.MORE
	lda NUMBLKS
	sec
	sbc CURBLK
	sta DIFF
	lda NUMBLKS+1
	sbc CURBLK+1
	sta DIFF+1
	bne SR.FULL
	lda DIFF
	cmp #$28
	bcs SR.FULL
	tay
	jmp SR.PARTIAL

SR.FULL
	ldy #$28
	sty DIFF

SR.PARTIAL
	lda CURBLK
	sta BLKLO
	lda CURBLK+1
	sta BLKHI
	jsr RECVING
	lda CURBLK
	sta BLKLO
	lda CURBLK+1
	sta BLKHI
	ldy DIFF	
	jsr WRITING

	lda BLKLO
	sta CURBLK
	lda BLKHI
	sta CURBLK+1

	* Now, need to see if we're over the size limit...

	cmp NUMBLKS+1	Compare high-order num blocks byte
	bcc SR.MORE
	lda BLKLO
	cmp NUMBLKS	Compare low-order num blocks byte
	bcc SR.MORE

	lda #CHR_ACK	SEND LAST ACK
	jsr PUTC
	lda #$00	Should be errors...
	jsr PUTC	SEND ERROR FLAG TO PC

	jsr COMPLETE
SR.DONE	rts

COMPLETE
	lda #$00	Reposition cursor to previous
	sta <CH		buffer row
	lda #$16
	jsr TABV
	ldy #PMSG14
	jsr SHOWMSG
	lda #$a1
	jsr COUT1
	jsr CROUT
COMPLETE.1
	jsr PAUSE
	rts

CURBLK	.db $00,$00
DIFF	.db $00,$00

*---------------------------------------------------------
* SENDING
* RECVING
*
* Read or write from zero to 40 ($28) blocks - inside
* a 64k Apple ][ buffer
*
* Input:
*   Y: Count of blocks
*   BLKLO: starting block (lo)
*   BLKHI: starting block (hi)
*---------------------------------------------------------
SENDING
	lda #PMSG06
	sta SR_WR_C
	lda #CHR_S
	sta SRCHR
	lda #CHR_SP
	sta SRCHROK
	jmp SR_COMN

RECVING
	lda #PMSG05
	sta SR_WR_C
	lda #CHR_V
	sta SRCHR
	lda #CHR_BLK
	sta SRCHROK

SR_COMN
	sty SRBCNT
	lda #H_BUF
	sta <CH
	lda #V_MSG	Message row
	jsr TABV
	ldy SR_WR_C
	jsr SHOWMSG

	lda #$00	Reposition cursor to beginning of
	sta <CH		buffer row
	lda #V_BUF
	jsr TABV

	jsr SRBLOX

	rts

*---------------------------------------------------------
* SRBLOX
*
* Read or write from zero to 40 ($28) blocks
* Starting from BIGBUF
*
* Input:
*   SRBCNT: Count of blocks
*   BLKLO: starting block (lo)
*   BLKHI: starting block (hi)
*---------------------------------------------------------
SRBLOX
	lda #BIGBUF	Connect the block pointer to the
	sta BLKPTR	beginning of the Big Buffer(TM)
	lda /BIGBUF
	sta BLKPTR+1

SRCALL

	lda SRCHR
	jsr CHROVER

	lda <CH
	sta <COL_SAV

	lda #V_MSG	Start printing at first number spot
	jsr TABV
	lda #H_NUM1
	sta <CH

	lda BLKLO	Increment the 16-bit block number
	clc
	adc #$01
	sta PRTPTR
	lda BLKHI
	bcc SR.NEXT
	clc
	adc #$01
SR.NEXT
	sta PRTPTR+1
	jsr PRTNUM	Print block number in decimial

	lda <COL_SAV	Reposition cursor to previous
	STA <CH		buffer row
	lda #V_BUF
	jsr TABV

	lda SRCHR	Are we receiving?
	cmp #CHR_V	  If so, load up our "R" character
	beq SR.1	  and branch around the sending code

	jsr SENDBLK	Send the current block
	jmp SRCOMN	Back to sending/receiving common

SR.1
	jsr RECVBLK	Receive a block

SRCOMN
	bne SRBAD
	lda SRCHROK
	jmp SROK

SRBAD	lda #CHR_X
SROK	jsr COUT1
	inc BLKLO
	bne SRNOB
	inc BLKHI
SRNOB	dec SRBCNT
	beq SRB.DONE
	jmp SRCALL

SRB.DONE	rts

SRBCNT	.db $00

*---------------------------------------------------------
* SENDBLK - Send a block with RLE
* CRC is sent to host
* BLKPTR points to full block to send - updated here
*---------------------------------------------------------
SENDBLK
	lda #$02
	sta <ZP

SENDMORE
	jsr SENDHBLK
	lda <CRC	Send the CRC of that block
	jsr PUTC
	lda <CRC+1
	jsr PUTC
	jsr GETC	Receive reply
	cmp #CHR_ACK	Is it ACK?  Loop back if NAK.
	bne SENDMORE
	inc <BLKPTR+1	Get next 256 bytes
	dec <ZP
	bne SENDMORE
	rts

*---------------------------------------------------------
* SENDHBLK - Send half a block with RLE
* CRC is computed and stored
* BLKPTR points to half block to send
*---------------------------------------------------------
SENDHBLK
	ldy #$00	Start at first byte
	sty <CRC	Clean out CRC
	sty <CRC+1
	sty <RLEPREV

SS1	lda (BLKPTR),Y	GET BYTE TO SEND
	jsr UPDCRC	UPDATE CRC
	tax		KEEP A COPY IN X
	sec		SUBTRACT FROM PREVIOUS
	sbc <RLEPREV
	stx <RLEPREV	SAVE PREVIOUS BYTE
	jsr PUTC	SEND DIFFERENCE
	beq SS3		WAS IT A ZERO?
	iny		NO, DO NEXT BYTE
	bne SS1		LOOP IF MORE TO DO
	rts		ELSE RETURN

SS2	jsr UPDCRC
SS3	iny		ANY MORE BYTES?
	beq SS4		NO, IT WAS 00 UP TO END
	lda (BLKPTR),Y	LOOK AT NEXT BYTE
	cmp <RLEPREV
	beq SS2		SAME AS BEFORE, CONTINUE
SS4	tya		DIFFERENCE NOT A ZERO
	jsr PUTC	SEND NEW ADDRESS
	bne SS1		AND GO BACK TO MAIN LOOP
	rts		OR RETURN IF NO MORE BYTES

SRCHR	.db CHR_V
SRCHROK	.db CHR_SP


*---------------------------------------------------------
* SENDFN - Send a file name
*
* Assumes input is at $0200
*---------------------------------------------------------
SENDFN
	ldx #$00	
FNLOOP	lda $0200,X
	jsr PUTC
	beq SENDFN.DONE
	inx
	bne FNLOOP
SENDFN.DONE
	rts


*---------------------------------------------------------
* RECVBLK - Receive a block with RLE
*
* BLKPTR points to full block to receive - updated here
*---------------------------------------------------------
RECVBLK
	lda #$02
	sta <ZP
	lda #CHR_ACK

RECVMORE
	tax
	ldy #$00	Clear out the new half-block
	tya
CLRLOOP	sta (BLKPTR),Y
	iny
	bne CLRLOOP
	txa
	jsr PUTC	Send ack/nak

	jsr RECVHBLK
	jsr GETC	Receive reply
	sta PCCRC	Receive the CRC of that block
	jsr GETC
	sta PCCRC+1
	jsr UNDIFF

	lda <CRC
	cmp PCCRC
	bne RECVERR
	lda <CRC+1
	cmp PCCRC+1
	bne RECVERR

RECBRANCH
	lda #CHR_ACK
	inc <BLKPTR+1	Get next 256 bytes
	dec <ZP
RECOK	bne RECVMORE
	lda #$00
	rts

RECVERR
	lda #CHR_NAK	CRC error, ask for a resend
	jmp RECVMORE

*---------------------------------------------------------
* RECVHBLK - Receive half a block with RLE
*
* CRC is computed and stored
*---------------------------------------------------------
RECVHBLK
	ldy #0		START AT BEGINNING OF BUFFER
RC1
	jsr GETC	GET DIFFERENCE
	beq RC2		IF ZERO, GET NEW INDEX
	sta (BLKPTR),Y	ELSE PUT CHAR IN BUFFER
	iny		AND INCREMENT INDEX
	bne RC1		LOOP IF NOT AT BUFFER END
	rts		ELSE RETURN
RC2
	jsr GETC	GET NEW INDEX
	tay		IN Y REGISTER
	bne RC1		LOOP IF INDEX <> 0
	rts		ELSE RETURN


*---------------------------------------------------------
* UNDIFF -  Finish RLE decompression and update CRC
*---------------------------------------------------------
UNDIFF	ldy #0
	sty <CRC	Clear CRC
	sty <CRC+1
	sty <RLEPREV	Initial base is zero
UDLOOP	lda (BLKPTR),Y	Get new difference
	clc
	adc <RLEPREV	Add to base
	jsr UPDCRC	Update CRC
	sta <RLEPREV	Accumulator is the new base
	sta (BLKPTR),Y 	Store real byte
	iny
	bne UDLOOP 	Repeat 256 times
	rts


*---------------------------------------------------------
* PUTC - Send accumulator out the serial line
*---------------------------------------------------------
PUTC
	pha		Push A onto the stack
PUTC1	lda $C000
	cmp #CHR_ESC	ESCAPE = ABORT
	beq PABORT

MOD1	lda $C089	CHECK STATUS BITS
	and #$70
	cmp #$10
	bne PUTC1	OUTPUT REG FULL, LOOP
	pla
MOD2	sta $C088	PUT CHARACTER
	rts


*---------------------------------------------------------
* GETC - GET A CHARACTER FROM SERIAL LINE (XY UNCHANGED)
*---------------------------------------------------------
GETC
	lda $C000
	cmp #CHR_ESC	ESCAPE = ABORT
	beq PABORT
MOD3	lda $C089	CHECK STATUS BITS
	and #$68
	cmp #$8
	bne GETC	INPUT REG EMPTY, LOOP
MOD4	lda $C088	GET CHARACTER
	rts

PABORT	jmp BABORT

SCOUNT	.db $00
