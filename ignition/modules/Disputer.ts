import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("Disputer", (m) => {
  const distributor = '0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae';
  const deployer = "0xfdA462548Ce04282f4B6D6619823a7C64Fdc0185";
  const disputer = m.contract("Disputer", [deployer, [], distributor]);
  return { disputer };
});