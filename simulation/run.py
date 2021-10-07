import os
import sys
import logging
import time
import random
import argparse
import atexit
import subprocess
import math

SERVER = None
HEADLESS = True
PLAYER_SESSION_DURATION = 25 # average (20-30), see player.sh

logging.basicConfig(format='%(asctime)s >>> %(message)s', datefmt='%H:%M:%S', level=logging.INFO)
log = logging.getLogger(__name__)

class Player():
    def __init__(self, start_time):
        self.start_time = start_time
        self.started = False
        self.process = None

    def run(self):
        self.started = True
        env = os.environ.copy()
        if HEADLESS:
            env['DISPLAY'] = ':99'
        self.process = subprocess.Popen(('./player.sh', SERVER), env=env)


def print_msg(num_players, duration):
    """
    https://wenku.baidu.com/view/68f1853a580216fc700afd74.html
    https://www.bbsmax.com/A/D8546x9VzE/
    """
    ave_concurrency = num_players * PLAYER_SESSION_DURATION / duration
    max_concurrency = ave_concurrency + 3 * math.sqrt(ave_concurrency)
    log.info('Simulation starting ...')
    log.info('    Ave concurrency ~= %.1f', ave_concurrency)
    log.info('    Max concurrency ~= %.1f (3 sigma)', max_concurrency)

def start_xvfb():
    from shutil import which
    if which('Xvfb') is None:
        print('Please install Xvfb first!')
        sys.exit(1)
    os.system('Xvfb :99 -screen 0 800x600x16 &')

def cleanup():
    os.system('pkill -f Xvfb')
    os.system('pkill -f xonotic-linux*')
    os.system('rm -rf Xonotic/.xonotic*')

def run():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        '-s', '--server', required=True,
        help='ip:port of server to connect')
    parser.add_argument(
        '-n', '--num_players', default=15, type=int,
        help='number of players to simulate')
    parser.add_argument(
        '-d', '--duration', default=300, type=int,
        help='duration of simulation (in seconds)')
    parser.add_argument(
        '--headless', dest='headless', action='store_true',
        help='headless mode (xvfb)')
    parser.add_argument(
        '--no-headless', dest='headless', action='store_false',
        help='visible mode')

    parser.set_defaults(headless=True)
    args = parser.parse_args()

    global SERVER, HEADLESS
    SERVER = args.server
    HEADLESS = args.headless

    now = time.time()
    end = now + args.duration + 30 + 3 # 30s added for max player session & allowance
    players = [Player(now + random.randrange(args.duration)) for i in range(args.num_players)]

    atexit.register(cleanup)
    if HEADLESS:
        start_xvfb()

    print_msg(args.num_players, args.duration)

    while True:
        now = time.time()
        if now >= end:
            break

        # exec ./player.sh for those start_time is up
        [p.run() for p in players if not p.started and now >= p.start_time]
        # prevent zombies/defunct
        [p.process.wait() for p in players if p.started and p.process.poll() is not None]

        # filter (keep) those in queue + running
        players = [p for p in players if not p.started or p.process.poll() is None]
        # size of players still running/active
        running = len([p for p in players if p.started])

        log.info('Status - running:%d queue:%d', running, len(players) - running)
        time.sleep(5)

    cleanup()
    print('Simulation ended')


if __name__ == '__main__':
    run()
