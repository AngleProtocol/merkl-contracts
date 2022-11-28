import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { TypedDataUtils } from 'eth-sig-util';
import { fromRpcSig } from 'ethereumjs-util';
import { BigNumber } from 'ethers';

export type TypePermit = {
  token: string;
  owner: string;
  value: BigNumber;
  deadline: number;
  v: number;
  r: Buffer;
  s: Buffer;
};

const EIP712Domain = [
  { name: 'name', type: 'string' },
  { name: 'version', type: 'string' },
  { name: 'chainId', type: 'uint256' },
  { name: 'verifyingContract', type: 'address' },
];

const Permit = [
  { name: 'owner', type: 'address' },
  { name: 'spender', type: 'address' },
  { name: 'value', type: 'uint256' },
  { name: 'nonce', type: 'uint256' },
  { name: 'deadline', type: 'uint256' },
];

export async function domainSeparator(
  name: string,
  verifyingContract: string,
  version = '1',
  chainId = 1337,
): Promise<string> {
  return (
    '0x' +
    TypedDataUtils.hashStruct('EIP712Domain', { name, version, chainId, verifyingContract }, { EIP712Domain }).toString(
      'hex',
    )
  );
}

const buildData = (
  owner: string,
  chainId: number,
  verifyingContract: string,
  deadline: number,
  spender: string,
  nonce: number,
  value: BigNumber,
  name: string,
  version: string,
) => ({
  primaryType: 'Permit',
  types: { Permit },
  domain: { name, version, chainId, verifyingContract },
  message: { owner, spender, value, nonce, deadline },
});

export async function signPermit(
  owner: SignerWithAddress,
  nonce: number,
  verifyingContract: string,
  deadline: number,
  spender: string,
  value: BigNumber,
  name: string,
  chainId = 1337,
  version = '1',
): Promise<TypePermit> {
  const data = buildData(owner.address, chainId, verifyingContract, deadline, spender, nonce, value, name, version);
  const signature = await owner._signTypedData(data.domain, data.types, data.message);
  const { v, r, s } = fromRpcSig(signature);

  return {
    token: verifyingContract,
    owner: owner.address,
    value: value,
    deadline: deadline,
    v: v,
    r: r,
    s: s,
  };
}
