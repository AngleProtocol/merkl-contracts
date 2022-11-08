import { utils, BigNumber, BigNumberish } from 'ethers'

export function mwei(number: BigNumberish): BigNumber {
  return utils.parseUnits(number.toString(), 'mwei')
}

// gweiToBN
export function gwei(number: BigNumberish): BigNumber {
  return utils.parseUnits(number.toString(), 'gwei')
}
function formatGwei(number: BigNumberish): string {
  return utils.formatUnits(number, 'gwei')
}

function ether(number: BigNumberish): BigNumber {
  return utils.parseUnits(number.toString(), 'ether')
}
function formatEther(number: BigNumberish): string {
  return utils.formatEther(number)
}

function dai(number: BigNumberish): BigNumber {
  return utils.parseUnits(number.toString(), 18)
}
function formatDai(number: BigNumberish): string {
  return utils.formatEther(number)
}

function usdc(number: BigNumberish): BigNumber {
  return utils.parseUnits(number.toString(), 6)
}
function formatUsdc(number: BigNumberish): string {
  return utils.formatUnits(number, 6)
}

function general(number: BigNumberish, decimal: number): BigNumber {
  return utils.parseUnits(number.toString(), decimal)
}
function formatGeneral(number: BigNumberish, decimal: number): string {
  return utils.formatUnits(number, decimal)
}

export const parseAmount = {
  ether,
  dai,
  usdc,
  gwei,
  general,
}

export const formatAmount = {
  ether: formatEther,
  dai: formatDai,
  usdc: formatUsdc,
  gwei: formatGwei,
  general: formatGeneral,
}

export function multByPow(
  number: number | BigNumber,
  pow: number | BigNumber,
): BigNumber {
  return utils.parseUnits(number.toString(), pow)
}

//
export function multBy10e15(number: number | BigNumber): BigNumber {
  return utils.parseUnits(number.toString(), 15)
}

// gweiToBN
export function multBy10e9(number: number): BigNumber {
  return utils.parseUnits(number.toString(), 'gwei')
}

// BNtoEth
export function divBy10e18(bigNumber: BigNumberish): number {
  return parseFloat(utils.formatUnits(bigNumber, 'ether'))
}

// BNtoEth
export function divBy10ePow(
  bigNumber: BigNumberish,
  pow: number | BigNumber,
): number {
  return parseFloat(utils.formatUnits(bigNumber, pow))
}
