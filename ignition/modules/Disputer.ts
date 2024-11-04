import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("Disputer", (m) => {
  const distributor = '0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae';
  const deployer = '0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701';
  const whitelist = [
    '0xeA05F9001FbDeA6d4280879f283Ff9D0b282060e',
    '0x0dd2Ea40A3561C309C03B96108e78d06E8A1a99B',
    '0xF4c94b2FdC2efA4ad4b831f312E7eF74890705DA'
  ];
  const disputer = m.contract("Disputer", [deployer, whitelist, distributor]);
  return { disputer };
});