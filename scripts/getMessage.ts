
import qs from "querystring";

async function main() {

  const chainId = 42161;
  const computeChainId = 42161;
  const amount = '1000000000'
  const capInUSD = 8 // Shall be an integer, maximum value distributed by the campaign in USD
  const targetToken = "0x0D914606f3424804FA1BbBE56CCC3416733acEC6"; // Radiant token
  const rewardToken = "0xAa25D25447102B523ceC16D19B2640d262ed1277" // mtwRDNT address. Can be found in `https://api.merkl.xyz/v3/createCampaign?chainId=<CHAIN_ID>&user=<ANY_EOA>`
  const startTimestamp = 1 // In Unix timestamps
  const endTimestamp = 10 // In Unix timestamps
  const blacklist: string[] = [] // Array of addresses to blacklist
  
  const url = `https://api.merkl.xyz/v3/payload?${qs.stringify({chainId, config: JSON.stringify({
    amount,
    creator: '0x0000000000000000000000000000000000000000',
    campaignType: 6, // Radiant
    targetToken,
    forwarders: [],
    capInUSD,
    rewardToken,
    startTimestamp,
    endTimestamp,
    blacklist,
    whitelist: [],
    computeChainId,
  })})}`;
  const res = await (await fetch(url)).json()

  // The tx to send will be in the `payload` field of the response
  console.log(res)
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
