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
           A seed's public half comes from openssl (PKCS#8 Ed25519, the DER the seed wraps
           directly), never from a hand-written curve implementation.
"""
import argparse
import base64
import plistlib
import shutil
import subprocess
import sys

ED25519_PKCS8_PREFIX = bytes.fromhex('302e020100300506032b657004220420')
ED25519_SPKI_PREFIX = bytes.fromhex('302a300506032b6570032100')


def decode(text, source):
    try:
        return base64.b64decode(''.join(text.split()), validate=True)
    except ValueError as error:
        sys.exit(f'{source} is not base64 EdDSA key material: {error}')


def public_key_from_seed(seed):
    openssl = shutil.which('openssl')
    if openssl is None:
        sys.exit('openssl is required to derive the Ed25519 public key from an exported seed')
    result = subprocess.run([openssl, 'pkey', '-inform', 'DER', '-pubout', '-outform', 'DER'],
                            input=ED25519_PKCS8_PREFIX + seed, capture_output=True)
    public = result.stdout
    if result.returncode != 0 or len(public) != 44 or not public.startswith(ED25519_SPKI_PREFIX):
        sys.exit('openssl could not derive the Ed25519 public key from this seed: '
                 + result.stderr.decode('utf-8', 'replace').strip())
    return public[12:]


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
