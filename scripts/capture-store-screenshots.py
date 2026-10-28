#!/usr/bin/env python3
"""Capture real debug UI with synthetic audio; never read the user's audio library."""
import argparse
import json
from pathlib import Path
import shutil
import struct
import subprocess
import time
import wave

ROOT = Path(__file__).resolve().parents[1]
SCENES = ['library', 'folder', 'player', 'queue', 'search', 'welcome']
TITLES = {
    'library': 'Your folders are your playlists',
    'folder': 'Play the whole folder',
    'player': 'Room to listen',
    'queue': 'See what plays next',
    'search': 'Find audio across your folders',
    'welcome': 'Your audio. Yours to play.',
}


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, stdout=subprocess.PIPE, **kwargs).stdout.strip()


def make_fixture(destination):
    destination.mkdir(parents=True, exist_ok=True)
    base = destination / 'silent-fixture.wav'
    with wave.open(str(base), 'wb') as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(8000)
        for _ in range(240):
            output.writeframes(b'\0' * 16000)
    encoded = destination / 'silent-fixture.m4a'
    run('afconvert', '-f', 'm4af', '-d', 'aac@44100', '-b', '64000', str(base), str(encoded))
    tree = {
        'Music/Acoustic Sessions': ['Morning Light', 'Open Skies', 'Quiet Hours', 'Soft Landing'],
        'Music/Piano Sketches': ['First Light', 'Rain at the Window', 'Sunday Afternoon'],
        'Podcasts/Slow Conversations': ['A Slower Start', 'Making Room for Ideas', 'The Art of Paying Attention'],
        'Voice Notes': ['A Melody to Remember', 'Ideas for the Weekend', 'Walking by the Water'],
    }
    audio = destination / 'My Audio'
    for folder, tracks in tree.items():
        path = audio / folder
        path.mkdir(parents=True, exist_ok=True)
        for title in tracks:
            shutil.copyfile(encoded, path / f'{title}.m4a')
    return audio


def wait_ready(path, process=None):
    deadline = time.monotonic() + 45
    while time.monotonic() < deadline:
        if path.exists():
            text = path.read_text()
            if text != 'ready':
                raise RuntimeError(text)
            return
        if process is not None and process.poll() is not None:
            raise RuntimeError('Capture app exited before rendering')
        time.sleep(0.25)
    raise TimeoutError(f'Timed out waiting for screenshot scene: {path.name}')


def capture_ios(app, fixture, output, runtime, kind, device_type):
    identifier = run('xcrun', 'simctl', 'create', f'Saptak Screenshots {kind}', device_type, runtime)
    print(f'Booting isolated {kind} simulator', flush=True)
    try:
        run('xcrun', 'simctl', 'boot', identifier)
        run('xcrun', 'simctl', 'bootstatus', identifier, '-b')
        run('xcrun', 'simctl', 'ui', identifier, 'appearance', 'light')
        run('xcrun', 'simctl', 'status_bar', identifier, 'override', '--time', '9:41',
            '--dataNetwork', 'wifi', '--wifiMode', 'active', '--wifiBars', '3',
            '--cellularMode', 'active', '--cellularBars', '4',
            '--batteryState', 'discharging', '--batteryLevel', '100')
        run('xcrun', 'simctl', 'install', identifier, str(app))
        container = Path(run('xcrun', 'simctl', 'get_app_container', identifier, 'com.playsaptak.app', 'data'))
        documents = container / 'Documents'
        documents.mkdir(exist_ok=True)
        root = documents / 'My Audio'
        shutil.copytree(fixture, root)
        ready = documents / 'screenshot-ready.txt'
        destination = output / kind
        destination.mkdir(parents=True, exist_ok=True)
        for number, scene in enumerate(SCENES, 1):
            ready.unlink(missing_ok=True)
            run('xcrun', 'simctl', 'launch', '--terminate-running-process', identifier, 'com.playsaptak.app',
                '--screenshot-scene', scene, '--screenshot-root', str(root), '--screenshot-ready', str(ready))
            wait_ready(ready)
            target = destination / f'{number:02d}-{scene}.png'
            run('xcrun', 'simctl', 'io', identifier, 'screenshot', '--type=png', str(target))
            print(f'Captured {kind}/{target.name}', flush=True)
    finally:
        subprocess.run(['xcrun', 'simctl', 'shutdown', identifier], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(['xcrun', 'simctl', 'delete', identifier], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def capture_mac(app, fixture, output):
    # A separate signed bundle identifier keeps the user's installed app/container isolated.
    container = Path.home() / 'Library/Containers/com.playsaptak.screenshots/Data'
    root = container / 'Documents/SaptakScreenshotFixture/My Audio'
    temporary = container / 'tmp/SaptakScreenshotCapture'
    ready = temporary / 'ready.txt'
    destination = output / 'mac'
    destination.mkdir(parents=True, exist_ok=True)
    scenes = ['welcome', 'library', 'folder', 'queue', 'search']
    for scene in scenes:
        temporary.mkdir(parents=True, exist_ok=True)
        ready.unlink(missing_ok=True)
        target = temporary / f'{scene}.png'
        if scene != 'welcome' and not root.exists():
            root.parent.mkdir(parents=True, exist_ok=True)
            shutil.copytree(fixture, root)
        log = (output / f'mac-{scene}.log').open('w')
        process = subprocess.Popen([str(app / 'Contents/MacOS/Saptak'), '--screenshot-scene', scene,
                                    '--screenshot-root', str(root), '--screenshot-ready', str(ready),
                                    '--screenshot-output', str(target)], stdout=log, stderr=log)
        try:
            wait_ready(ready, process)
            number = ['library', 'folder', 'queue', 'search', 'welcome'].index(scene) + 1
            window_id = target.with_suffix('.png.windowid').read_text().strip()
            # WindowServer can briefly lag behind the app's first rendered frame.
            for attempt in range(3):
                try:
                    run('screencapture', '-x', '-o', '-l', window_id, str(destination / f'{number:02d}-{scene}.png'))
                    break
                except subprocess.CalledProcessError:
                    if attempt == 2:
                        raise
                    time.sleep(1)
            print(f'Captured mac/{scene}', flush=True)
        finally:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            log.close()


def make_index(output):
    entries = []
    cards = []
    for image in sorted(output.glob('*/*.png')):
        data = image.read_bytes()
        if data[:8] != b'\x89PNG\r\n\x1a\n':
            raise ValueError('Not a PNG screenshot')
        width, height = struct.unpack('>II', data[16:24])
        allowed = {
            'iphone': {(1179, 2556), (1206, 2622)},
            'iphone-max': {(1260, 2736), (1290, 2796), (1320, 2868)},
            'ipad': {(2048, 2732), (2064, 2752)},
            'mac': {(1280, 800), (1440, 900), (2560, 1600), (2880, 1800)},
        }
        if (width, height) not in allowed[image.parent.name]:
            raise ValueError(f'Unexpected screenshot dimensions: {image.name}: {width}x{height}')
        if data[25] in (4, 6):
            raise ValueError(f'Screenshot includes an alpha channel: {image}')
        scene = image.stem.split('-', 1)[1]
        name = image.relative_to(output).as_posix()
        entries.append({'file': name, 'width': width, 'height': height, 'scene': scene})
        cards.append(f'<article><a href="{name}"><img src="{name}" loading="lazy"></a><h2>{TITLES[scene]}</h2><p>{name} · {width} × {height}</p></article>')
    (output / 'manifest.json').write_text(json.dumps(entries, indent=2) + '\n')
    (output / 'index.html').write_text('''<!doctype html><html lang="en"><meta charset="utf-8"><title>Saptak App Store Screenshots</title>
<style>body{background:#fbf5e9;color:#30212f;font:16px system-ui;margin:36px}h1{font:40px Georgia}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:28px}article{background:white;padding:16px;border:1px solid #b9bf8a;border-radius:16px}img{width:100%;height:460px;object-fit:contain}h2{font-size:18px}p{font-size:13px;color:#695466}</style>
<h1>Saptak</h1><p>Your audio. Yours to play. · Actual app captures with synthetic audio only.</p><main>''' + ''.join(cards) + '</main></html>')


def prepare_uploads(output):
    tools = output / '.tools'
    tools.mkdir(exist_ok=True)
    normalizer = tools / 'normalize-screenshots'
    run('swiftc', '-module-cache-path', '/tmp/SaptakScreenshotModuleCache',
        str(ROOT / 'scripts/normalize-screenshots.swift'), '-o', str(normalizer))
    upload = output / 'app-store'
    print(run(str(normalizer), str(output), str(upload)), flush=True)
    make_index(upload)
    return upload


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--ios-app', type=Path)
    parser.add_argument('--mac-app', type=Path)
    parser.add_argument('--runtime', default='com.apple.CoreSimulator.SimRuntime.iOS-27-0')
    parser.add_argument('--devices', nargs='+', choices=['iphone', 'iphone-max', 'ipad'], default=['iphone', 'ipad'])
    args = parser.parse_args()
    if not args.ios_app and not args.mac_app:
        parser.error('Provide --ios-app or --mac-app')
    output = args.output.resolve()
    if output.exists():
        parser.error('Choose a new output directory; existing screenshots will not be overwritten')
    output.mkdir(parents=True)
    fixture_root = output / '.fixtures'
    fixture = make_fixture(fixture_root)
    specs = {'iphone': 'com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro',
             'iphone-max': 'com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro-Max',
             'ipad': 'com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB'}
    if args.ios_app:
        for device in args.devices:
            capture_ios(args.ios_app.resolve(), fixture, output, args.runtime, device, specs[device])
    if args.mac_app:
        capture_mac(args.mac_app.resolve(), fixture, output)
    upload = prepare_uploads(output)
    print(f'Review screenshots: {upload / "index.html"}', flush=True)


if __name__ == '__main__':
    main()
