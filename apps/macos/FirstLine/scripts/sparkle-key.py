"""[INPUT] --plist <Info.plist> plus exactly one signing-key source: --key-file <exported seed>
         (32-byte seed or 96-byte seed+public, as Sparkle generate_keys -x writes it) or
         --generate-keys <path> [--account <name>] to read the Keychain key's public half.
[OUTPUT] Exit 0 and print the matched base64 public key when the signing key's public half equals
         SUPublicEDKey in the plist. Exit 1 with the reason otherwise. No file is written.
[POS] apps/macos/FirstLine/scripts/sparkle-key.py - the key-pair gate used by publish-appcast.sh
      before any feed is generated.
[PROTOCOL] Sparkle's generate_appcast only warns when SUPublicEDKey does not match the signing key,
           and sign_update --verify derives its own public key from that same private key, so
           neither proves the installed app can verify the feed. This script is the only proof.
           A seed's public half comes from openssl (PKCS#8 Ed25519) when that openssl can derive
           Ed25519, which macOS's bundled LibreSSL cannot. The built-in fallback is a small RFC 8032
           implementation: security-sensitive code that needs independent review, proven against an
           RFC 8032 test vector by scripts/test-release-config.py. Never skip this proof.
"""
import argparse
import base64
import hashlib
import plistlib
import shutil
import subprocess
import sys

ED25519_PKCS8_PREFIX = bytes.fromhex('302e020100300506032b657004220420')
ED25519_SPKI_PREFIX = bytes.fromhex('302a300506032b6570032100')
PRIME = 2 ** 255 - 19


def decode(text, source):
    try:
        return base64.b64decode(''.join(text.split()), validate=True)
    except ValueError as error:
        sys.exit(f'{source} is not base64 EdDSA key material: {error}')


def invert(value):
    return pow(value, PRIME - 2, PRIME)


def public_key_from_seed_builtin(seed):
    d = -121665 * invert(121666) % PRIME

    def add(one, other):
        x1, y1, z1, t1 = one
        x2, y2, z2, t2 = other
        product = d * t1 * t2 % PRIME
        x = (x1 * y2 + x2 * y1) * invert(1 + product) % PRIME
        y = (y1 * y2 + x1 * x2) * invert(1 - product) % PRIME
        return x, y, z1 * z2 % PRIME, x * y % PRIME

    def multiply(point, scalar):
        result = (0, 1, 1, 0)
        while scalar:
            if scalar & 1:
                result = add(result, point)
            point = add(point, point)
            scalar >>= 1
        return result

    digest = hashlib.sha512(seed).digest()
    scalar = int.from_bytes(digest[:32], 'little')
    scalar = (scalar & ((1 << 254) - 8)) | (1 << 254)
    y = 4 * invert(5) % PRIME
    x_squared = (y * y - 1) * invert(d * y * y + 1) % PRIME
    x = pow(x_squared, (PRIME + 3) // 8, PRIME)
    if (x * x - x_squared) % PRIME:
        x = x * pow(2, (PRIME - 1) // 4, PRIME) % PRIME
    if x % 2:
        x = PRIME - x
    x, y, z, _ = multiply((x, y, 1, x * y % PRIME), scalar)
    x, y = x * invert(z) % PRIME, y * invert(z) % PRIME
    bits = [(y >> index) & 1 for index in range(255)] + [x & 1]
    return bytes(sum(bits[index * 8 + offset] << offset for offset in range(8)) for index in range(32))


def public_key_from_seed(seed):
    openssl = shutil.which('openssl')
    reason = 'openssl is not on PATH'
    if openssl is not None:
        result = subprocess.run([openssl, 'pkey', '-inform', 'DER', '-pubout', '-outform', 'DER'],
                                input=ED25519_PKCS8_PREFIX + seed, capture_output=True)
        public = result.stdout
        if result.returncode == 0 and len(public) == 44 and public.startswith(ED25519_SPKI_PREFIX):
            return public[12:]
        lines = result.stderr.decode('utf-8', 'replace').strip().splitlines()
        reason = f'{openssl} cannot derive Ed25519 keys' + (f': {lines[-1]}' if lines else '')
    print(f'warning: {reason}; using the built-in RFC 8032 derivation', file=sys.stderr)
    return public_key_from_seed_builtin(seed)


def public_key_from_file(path):
    try:
        with open(path, 'rb') as handle:
            raw = decode(handle.read().decode('utf-8', 'replace'), path)
    except OSError as error:
        sys.exit(f'cannot read signing key {path}: {error.strerror}')
    if len(raw) == 32:
        return public_key_from_seed(raw)
    if len(raw) == 96:
        return raw[64:]
    sys.exit(f'{path} is {len(raw)} bytes; Sparkle exports a 32-byte seed or 96-byte seed+public key')


def public_key_from_keychain(tool, account):
    result = subprocess.run([tool, '-p', '--account', account], capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(result.stderr.strip() or f'{tool} -p exited {result.returncode}')
    return decode(result.stdout, f'{tool} -p')


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--plist', required=True)
    parser.add_argument('--key-file')
    parser.add_argument('--generate-keys')
    parser.add_argument('--account', default='writeitdown')
    arguments = parser.parse_args()
    if (arguments.key_file is None) == (arguments.generate_keys is None):
        parser.error('pass exactly one of --key-file or --generate-keys')

    with open(arguments.plist, 'rb') as handle:
        declared = plistlib.load(handle).get('SUPublicEDKey')
    if not isinstance(declared, str):
        sys.exit(f'{arguments.plist} has no SUPublicEDKey string')
    declared = decode(declared, 'SUPublicEDKey')
    if len(declared) != 32:
        sys.exit('SUPublicEDKey must be the raw 32-byte Ed25519 public key')

    signing = (public_key_from_file(arguments.key_file) if arguments.key_file
               else public_key_from_keychain(arguments.generate_keys, arguments.account))
    if signing != declared:
        sys.exit('The update signing key does not match SUPublicEDKey in '
                 f'{arguments.plist} (signing key public half {base64.b64encode(signing).decode()}, '
                 f'plist {base64.b64encode(declared).decode()}); installed copies could never verify this feed')
    print(base64.b64encode(declared).decode())


if __name__ == '__main__':
    main()
