ENTRY(_user_start)
PHDRS {
  text PT_LOAD FLAGS(5);
  rodata PT_LOAD FLAGS(4);
  data PT_LOAD FLAGS(6);
}
SECTIONS {
  . = 0x400000;
  .text : { *(.text .text.*) } :text
  . = ALIGN(4096);
  .rodata : { *(.rodata .rodata.*) } :rodata
  . = ALIGN(4096);
  .data : { *(.data .data.*) } :data
  .bss : { *(COMMON) *(.bss .bss.*) } :data
  /DISCARD/ : { *(.eh_frame*) *(.comment) *(.note*) }
}
