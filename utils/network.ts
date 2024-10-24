import 'dotenv/config';

export function nodeUrl(networkName: string): string {
  if (networkName) {
    const uri = process.env['ETH_NODE_URI_' + networkName.toUpperCase()];
    if (uri && uri !== '') {
      return uri;
    }
  }

  let uri = process.env.ETH_NODE_URI;
  if (uri) {
    uri = uri.replace('{{networkName}}', networkName);
  }
  if (!uri || uri === '') {
    if (networkName === 'localhost') {
      return 'http://localhost:8545';
    }
    return '';
  }
  if (uri.indexOf('{{') >= 0) {
    throw new Error(`invalid uri or network not supported by node provider : ${uri}`);
  }
  return uri;
}

export function etherscanKey(networkName: string): string {
  if (networkName) {
    const key = process.env[networkName.toUpperCase() + '_ETHERSCAN_API_KEY'];
    if (key && key !== '') {
      return key;
    }
  }
  return '';
}

export function getMnemonic(networkName: string): string {
  if (networkName) {
    const mnemonic = process.env['MNEMONIC_' + networkName.toUpperCase()];
    if (mnemonic && mnemonic !== '') {
      return mnemonic;
    }
  }

  const mnemonic = process.env.MNEMONIC;
  if (!mnemonic || mnemonic === '') {
    return 'test test test test test test test test test test test junk';
  }
  return mnemonic;
}

export function accounts(networkName: string): { mnemonic: string; count: number } {
  return { mnemonic: getMnemonic(networkName), count: 20 };
}

export function getPkey(): string {
  if (process.env.DEPLOYER_PRIVATE_KEY && process.env.DEPLOYER_PRIVATE_KEY !=='') {
    return process.env.DEPLOYER_PRIVATE_KEY;
  } else {
    return '0x0000000000000000000000000000000000000000000000000000000000000000';
  }
}

export function getMerklAccount(): { mnemonic: string; count: number } {
  if (process.env.MNEMONIC_MERKL_DEPLOYER && process.env.MNEMONIC_MERKL_DEPLOYER !=='') {
    return { mnemonic: process.env.MNEMONIC_MERKL_DEPLOYER, count: 20 };
  } else {
    return  { mnemonic: '', count: 20 };
  }
}
