import glob
import json
import os
import select
import sys
import time

ACTIONS = {'Назад': (1, 8), 'Вперёд': (1, 16), 'Средняя кнопка': (1, 4), 'Смена DPI': (2, 1), 'DPI +': (2, 2), 'DPI −': (2, 3), 'Отключить': (0, 0)}


def devices():
    result = []
    for path in glob.glob('/sys/class/hidraw/hidraw*/device'):
        try:
            with open(path + '/uevent') as f:
                identity = f.read()
            if ':1.1/' not in os.path.realpath(path):
                continue
            for product in ('F50F', 'F50D'):
                if 'HID_ID=0003:00003554:0000' + product in identity:
                    result.append((product, '/dev/' + path.split('/')[-2]))
        except OSError:
            pass
    return sorted(result, reverse=True)


def exchange(fd, command, address=0, payload=b''):
    packet = bytearray(17)
    packet[0:2] = bytes((8, command))
    packet[3:6] = bytes((address >> 8, address & 255, len(payload)))
    packet[6:6 + len(payload)] = payload
    packet[-1] = (0x55 - sum(packet[:-1])) & 255
    os.write(fd, packet)
    end = time.monotonic() + 1
    while time.monotonic() < end:
        if not select.select([fd], [], [], max(0, end - time.monotonic()))[0]:
            break
        reply = os.read(fd, 64)
        if len(reply) >= 17 and reply[0] == 8 and reply[1] == command and sum(reply[:17]) % 256 == 0x55:
            if reply[2] != 0:
                raise OSError('device rejected command')
            if command in (7, 8) and reply[3:5] != packet[3:5]:
                continue
            return reply[6:16]
    raise OSError('mouse did not respond')


def read(fd, address, length):
    return exchange(fd, 8, address, bytes(length))[:length]


def sealed(data):
    if sum(data) % 256 != 0x55:
        raise OSError('invalid checksum')
    return data


def run(fd, product):
    if product == 'F50D' and exchange(fd, 3)[0] != 1:
        raise OSError('mouse offline')
    if len(sys.argv) == 3:
        button, action = sys.argv[1:]
        if button not in ('back', 'forward') or action not in ACTIONS:
            raise ValueError('invalid assignment')
        cls, value = ACTIONS[action]
        data = bytes((cls, value, 0, (0x55 - cls - value) & 255))
        address = 108 if button == 'back' else 112
        exchange(fd, 7, address, data)
        if read(fd, address, 4) != data:
            raise OSError('assignment not confirmed')
    battery = exchange(fd, 4)
    index = sealed(read(fd, 4, 2))[0]
    if index > 7:
        raise OSError('invalid DPI stage')
    dpi = sealed(read(fd, 12 + 4 * index, 4))
    x = (((dpi[2] >> 2) & 3) * 256 + dpi[0] + 1) * 50
    buttons = {}
    for name, address in (('back', 108), ('forward', 112)):
        data = sealed(read(fd, address, 4))
        buttons[name] = next((label for label, pair in ACTIONS.items() if pair == (data[0], data[1]) and data[2] == 0), 'Другое')
    return {'battery': battery[0] if battery[0] <= 100 else None, 'charging': battery[1] == 1, 'dpi': x, 'transport': 'USB' if product == 'F50F' else 'Радиоприёмник', 'buttons': buttons}


errors = []
for product, path in devices():
    try:
        fd = os.open(path, os.O_RDWR | os.O_NONBLOCK)
        try:
            print(json.dumps(run(fd, product), ensure_ascii=False))
            break
        finally:
            os.close(fd)
    except (OSError, ValueError) as error:
        errors.append(str(error))
        if len(sys.argv) > 1:
            break
else:
    pass
if errors and (len(sys.argv) > 1 or len(errors) == len(devices())):
    print(json.dumps({'error': '; '.join(errors)}, ensure_ascii=False))
elif not devices():
    print(json.dumps({'error': 'Мышь не найдена'}, ensure_ascii=False))
