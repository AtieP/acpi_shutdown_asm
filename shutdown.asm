org 0x7c00
bits 16

jmp short set_cs

set_cs:
	jmp 0x0000:main

main:
	xor ax, ax
	mov ds, ax
	mov es, ax
	cli
	mov ss, ax
	mov sp, 0x7c00

	lgdt [gdtr]

	; protected mode but in the actually
	; based way
	smsw ax
	or al, 1
	lmsw ax
	jmp 0x08:pm

bits 32
pm:
	mov ax, 0x10
	mov ds, ax
	mov es, ax
	mov fs, ax
	mov gs, ax
	mov ss, ax

	mov eax, 0xe0000 - 16

rsdp_find:
	add eax, 16
	cmp eax, 0xe0000 + 0x20000
	jge rsdp_error

	cmp [eax], dword "RSD "
	je .maybe

	jmp rsdp_find

.maybe:
	cmp [eax+4], dword "PTR "
	jne rsdp_find

get_rsdt:
	mov eax, [eax+16]
	cmp [eax], dword "RSDT"
	jne rsdt_error

get_fadt:
	mov ecx, [eax+4]
	sub ecx, 36
	shl ecx, 2
	inc ecx
	add eax, 36

.loop:
	mov ebx, [eax]
	cmp [ebx], dword "FACP"
	je parse_dsdt
	add eax, 4
	loop .loop
	jmp fadt_error

parse_dsdt:
	mov [fadt], ebx
	mov edx, ebx

	mov eax, [edx+40]

	; find the _S5_ package. it contains
	; the necessary sleep values
	mov ecx, [eax+4]
	sub ecx, 36
	inc ecx
	add eax, 36

.loop:
	cmp [eax], dword "_S5_"
	je parse_s5

	inc eax

	loop .loop
	jmp s5_error

parse_s5:
	add eax, 4
	; ensure this is a package.
	; it should be anyways but we should assert
	cmp [eax], byte 0x12
	jne s5_error

	; skip PkgLength. it is a field in packages that indicates the length.
	; get how many extra bytes, the amount is in the higher 2 bits
	movzx ebx, byte [eax]
	and ebx, 11000000b
	shr ebx, 6
	inc ebx
	add eax, ebx
	cmp [eax], byte 2
	jl s5_error

	add eax, 2

	call parse_aml_int
	mov [.pm1a_cnt_slp_typ5], dl

	call parse_aml_int
	mov [.pm1b_cnt_slp_typ5], dl

	; enable acpi mode if smm exists
	mov ebx, [fadt]
	mov dx, [ebx+48]
	test dx, dx
	jz .send_pm1a

	mov al, [ebx+52]

	test al, al
	jz .send_pm1a

	out dx, al
	mov ecx, 100

.poll:
	in al, 0x80
	loop .poll

.send_pm1a:

	; send slp typ5 to pm1a
	mov dx, [ebx+64]
	in ax, dx
	and ax, 0xe3ff
	movzx cx, byte [.pm1a_cnt_slp_typ5]
	shl cx, 10
	or cx, 1 << 13 ; slp_en
	or ax, cx
	out dx, ax

	; if pm1b block exists send there too
	mov dx, [ebx+68]
	cmp dx, 0x00
	jne .wait
	in ax, dx
	and ax, 0xe3ff
	movzx cx, byte [.pm1b_cnt_slp_typ5]
	shl cx, 10
	or cx, 1 << 3
	or ax, cx
	out dx, ax

.wait:
	jmp $

.pm1a_cnt_slp_typ5: db 0x00
.pm1b_cnt_slp_typ5: db 0x00

; data: eax
; out: dl: data, eax: points to next item
parse_aml_int:
	cmp [eax], byte 0x00
	je .zero

	cmp [eax], byte 0x01
	je .one

	cmp [eax], byte 0xff
	je .ones

	cmp [eax], byte 0x0a
	je .byte

	cmp [eax], byte 0x0b
	je .word

	; dword
	cmp [eax], byte 0x0c
	je .dword

	; qword
	cmp [eax], byte 0x0e
	je .qword

	jmp parse_error

.zero:
	xor dl, dl
	inc eax
	ret

.one:
	mov dl, 1
	inc eax
	ret

.ones:
	mov dl, 0xff
	inc eax
	ret

.byte:
	mov dl, [eax+1]
	add eax, 2
	ret

.word:
	mov dl, [eax+1]
	add eax, 3
	ret

.dword:
	mov dl, [eax+1]
	add eax, 5
	ret

.qword:
	mov dl, [eax+1]
	add eax, 9
	ret

rsdp_error:
	mov [0xb8000], word "P2"
	jmp $

rsdt_error:
	mov [0xb8000], word "R2"
	jmp $

fadt_error:
	mov [0xb8000], word "F2"
	jmp $

s5_error:
	mov [0xb8000], word "S2"
	jmp $

parse_error:
	mov [0xb8000], word "A2"
	jmp $

gdt:
	dq 0
	db 0
	dd 0
	db 0b10011010
	db 0b11001111
	db 0
	db 0
	dd 0
	db 0b10010010
	db 0b11001111
	db 0

gdtr:
	dw gdtr - gdt - 1
	dd gdt

fadt: dd 0

times 510 - ($ - $$) db 0x00
dw 0xaa55
