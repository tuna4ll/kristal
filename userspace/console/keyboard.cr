# scancode set 1, us layout
module Keyboard
  PLAIN = "\0\e1234567890-=\b\tqwertyuiop[]\n\0asdfghjkl;'`\0\\zxcvbnm,./\0*\0 "
  SHIFT = "\0\e!@#$%^&*()_+\b\tQWERTYUIOP{}\n\0ASDFGHJKL:\"~\0|ZXCVBNM<>?\0*\0 "
  @@shift = false
  @@control = false
  @@extended = false

  def self.translate(code : UInt8) : UInt8
    if code == 0xe0
      @@extended = true
      return 0_u8
    end
    extended = @@extended
    @@extended = false
    release = code & 0x80 != 0
    key = code & 0x7f
    if key == 0x2a || key == 0x36
      @@shift = !release
      return 0_u8
    elsif key == 0x1d
      @@control = !release
      return 0_u8
    end
    return 0_u8 if release || extended || key >= 58
    value = (@@shift ? SHIFT : PLAIN).to_unsafe[key]
    value = value & 0x1f_u8 if @@control && value >= 0x40
    value
  end
end
