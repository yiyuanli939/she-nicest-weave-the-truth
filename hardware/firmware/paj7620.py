# PAJ7620U2 手势传感器最小驱动(MicroPython)。
# 初始化寄存器表取自本机小智固件(deskemoji gesture_sensor.cc),I2C 地址 0x73。
# 本项目只用它做一件事:hand() —— 眼前有没有手在挥(校准"看电脑方向"时锁定用)。
import time

ADDR = 0x73

# (bank 切换内联在表里:0xEF 0x00/0x01)
_INIT = bytes.fromhex(
    "EF00322933013400350136003707381739063A123F00400241FF4201462D470F"
    "483C49004A1E4B004C204D004E1A4F145000511052005C025D005E105F3F6027"
    "61286200630364F7650366D96703680169C86A406D046E006F00708071007200"
    "730074F0750080428144820483208420850086108700880589188A108B018C37"
    "8D008EF08F8190069106921E930D940A950A960C9705980A99419A149B0A9C3F"
    "9D339EAE9FF9A048A113A210A308A430A519A610A708A824A904AA1EAB1ECC19"
    "CD0BCE13CF64D021D10FD288E001E104E241E3D6E400E50CE60AE700E800E900"
    "EE07EF01001E011E020F03100402050006B00704080D090E0A9C0B040C050D0F"
    "0E020F1210021102120013011405150716051707180119041A051B0C1C2A1D01"
    "1E00210022002300250126002739287F290830033100321A331A340735073601"
    "37FF383639073A003EFF3F00407741404200433044A0455C4600470048584A1E"
    "4B1E4C004D004EA04F8050005100520053005400578059105A085B945CE85D08"
    "5E3D5F9960456140632D6402659666006797680169CD6A016BB06C046D2C6E01"
    "6F3271007201733574007533763177017C847D037E01"
)


class PAJ7620:
    def __init__(self, i2c):
        self.i2c = i2c
        self.ok = False
        try:
            # 唤醒:休眠时第一笔 I2C 会 NACK,连敲两次
            for _ in range(3):
                try:
                    self.i2c.writeto_mem(ADDR, 0xEF, b"\x00")
                    break
                except OSError:
                    time.sleep_ms(10)
            for i in range(0, len(_INIT), 2):
                self.i2c.writeto_mem(ADDR, _INIT[i], _INIT[i + 1:i + 2])
            self.i2c.writeto_mem(ADDR, 0xEF, b"\x00")
            self.i2c.readfrom_mem(ADDR, 0x43, 2)   # 清一次标志
            self.ok = True
        except OSError:
            self.ok = False   # 传感器不在/接触不良:校准退化为按 BOOT 键锁定

    ## 眼前是否有手势活动(读并清手势标志)
    def hand(self) -> bool:
        if not self.ok:
            return False
        try:
            f = self.i2c.readfrom_mem(ADDR, 0x43, 2)
            return f[0] != 0 or f[1] != 0
        except OSError:
            return False
