#!/usr/bin/env python3
"""Read LAMZU CompX report 8 (OpenMouse protocol), USB before 1K receiver."""
import glob
import json
import os
import select
import signal
import time


def devices():
    result = []
    for path in glob.glob('/sys/class/hidraw/hidraw*/device'):
        try:
            with open(path + '/uevent') as stream:
                identity = stream.read(4096)
            if ':1.1/' not in os.path.realpath(path):
                continue
            for product in ('F50F', 'F50D'):
                if 'HID_ID=0003:00003554:0000' + product in identity:
                    result.append((product, '/dev/' + path.split('/')[-2]))
        except OSError:
            pass
    return sorted(result, reverse=True)


def exchange(fd, command, address=0, length=0):
    packet = bytearray(17)
    packet[0:2] = bytes((8, command))
    packet[3:6] = bytes((address >> 8, address & 255, length))
    packet[-1] = (0x55 - sum(packet[:-1])) & 255
    os.write(fd, packet)
    end = time.monotonic() + 0.8
    while time.monotonic() < end:
        if not select.select([fd], [], [], max(0, end - time.monotonic()))[0]:
            break
        reply = os.read(fd, 64)
        if len(reply) != 17 or reply[0] != 8 or reply[1] != command or sum(reply) % 256 != 0x55:
            continue
        if command == 8 and reply[3:5] != packet[3:5]:
            continue
        if reply[2] != 0:
            raise OSError('Device rejected status request')
        return reply[6:16]
    raise OSError('Mouse asleep, disconnected or not responding')


def field(fd, address, length):
    data = exchange(fd, 8, address, length)[:length]
    if sum(data) % 256 != 0x55:
        raise OSError('Invalid DPI checksum')
    return data


def read_status(fd, product):
    if product == 'F50D' and exchange(fd, 3)[0] != 1:
        raise OSError('Wireless mouse offline')
    battery = exchange(fd, 4)
    result = {'connected': True, 'battery': battery[0] if battery[0] <= 100 else None,
              'charging': battery[1] == 1, 'transport': 'usb' if product == 'F50F' else 'wireless',
              'product': product.lower(), 'dpi': 0}
    try:
        index = field(fd, 4, 2)[0]
        if index > 7:
            raise OSError('Invalid DPI stage')
        dpi = field(fd, 12 + 4 * index, 4)
        result['dpi'] = (((dpi[2] >> 2) & 3) * 256 + dpi[0] + 1) * 50
    except OSError as error:
        result['error'] = str(error)
    return result


def main():
    errors = []
    available = devices()
    for product, path in available:
        try:
            fd = os.open(path, os.O_RDWR | os.O_NONBLOCK)
            try:
                return read_status(fd, product)
            finally:
                os.close(fd)
        except OSError as error:
            errors.append(str(error))
    return {'connected': None if available else False, 'present': bool(available),
            'error': '; '.join(errors) if errors else 'LAMZU not connected'}


if __name__ == '__main__':
    signal.alarm(8)
    print(json.dumps(main()))
