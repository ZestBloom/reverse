import { loadStdlib } from "@reach-sh/stdlib";
import launchToken from "@reach-sh/stdlib/launchToken.mjs";
import assert from "assert";

const [, , infile] = process.argv;

(async () => {
  console.log("START");

  const backend = await import(`./build/${infile}.main.mjs`);
  const stdlib = await loadStdlib();
  const startingBalance = stdlib.parseCurrency(1000);

  const accAlice = await stdlib.newTestAccount(startingBalance);
  const accBob = await stdlib.newTestAccount(startingBalance);
  const accs = await Promise.all(
    Array.from({ length: 10 }).map(() => stdlib.newTestAccount(startingBalance))
  );
  //await stdlib.wait(10)

  const zorkmid = await launchToken(stdlib, accAlice, "zorkmid", "ZMD");
  const gil = await launchToken(stdlib, accBob, "gil", "GIL");
  await accAlice.tokenAccept(gil.id);
  await accBob.tokenAccept(zorkmid.id);

  const getBalance = async (who) =>
    stdlib.formatCurrency(await stdlib.balanceOf(who), 4);

  const beforeAlice = await getBalance(accAlice);
  const beforeBob = await getBalance(accBob);

  const getParams = (addr) => ({
    addr,
    addr2: addr,
    addr3: addr,
    addr4: addr,
    addr5: addr,
    amt: stdlib.parseCurrency(1),
    tok: zorkmid.id,
    token_name: "",
    token_symbol: "",
    secs: 0,
    secs2: 0,
  });

  const signal = () => {};

  const voteHelper = (ctc) => async (vote) =>
    ((v) => ctc.a.vote(v))(vote === "yes" ? 1 : 2);

  const getVoteHelper = (ctc) => async (vote) =>
    stdlib.bigNumberToNumber((await ctc.v[vote]())[1]);

  // (1) can be deleted before activation
  console.log("CAN DELETED INACTIVE");
  (async (acc) => {
    let addr = acc.networkAccount.addr;
    let ctc = acc.contract(backend);
    Promise.all([
      backend.Constructor(ctc, {
        getParams: () => getParams(addr),
        signal,
      }),
      backend.Verifier(ctc, {}),
    ]).catch(console.dir);
    let appId = await ctc.getInfo();
    console.log(appId);
  })(accAlice);
  await stdlib.wait(4);

  // (2) constructor receives payment on activation
  console.log("CAN ACTIVATE WITH PAYMENT");
  await (async (acc, acc2) => {
    let addr = acc.networkAccount.addr;
    let ctc = acc.contract(backend);
    Promise.all([
      backend.Constructor(ctc, {
        getParams: () => getParams(addr),
        signal,
      }),
    ]);
    let appId = await ctc.getInfo();
    console.log(appId);
    let ctc2 = acc2.contract(backend, appId);
    Promise.all([backend.Contractee(ctc2, {})]);
    await stdlib.wait(50);
  })(accAlice, accBob);

  const afterAlice = await getBalance(accAlice);
  const afterBob = await getBalance(accBob);

  const diffAlice = Math.round(afterAlice - beforeAlice);
  const diffBob = Math.round(afterBob - beforeBob);

  console.log(
    `Alice went from ${beforeAlice} to ${afterAlice} (${diffAlice}).`
  );
  console.log(`Bob went from ${beforeBob} to ${afterBob} (${diffBob}).`);

  assert.equal(diffAlice, 1);
  assert.equal(diffBob, -1);

  // (3) can purchase
  console.log("CAN PURCHASE AT START");
  await (async (acc, acc2) => {
    let addr = acc.networkAccount.addr;
    let ctc = acc.contract(backend);
    Promise.all([
      backend.Constructor(ctc, {
        getParams: () => getParams(addr),
        signal,
      }),
    ]);
    let appId = await ctc.getInfo();
    console.log(appId);
    let ctc2 = acc2.contract(backend, appId);
    Promise.all([
      backend.Contractee(ctc2, {}),
      backend.Auctioneer(ctc2, {
        ...stdlib.hasConsoleLogger,
        getParams: () => ({
          token: gil.id,
          addr: addr,
          addr2: addr,
          creator: addr,
          startPrice: stdlib.parseCurrency(100),
          floorPrice: stdlib.parseCurrency(10),
          endConsensusTime: 0,
        }),
        signal: () => {
          console.log("AUCTION CREATED");
        },
        close: () => {},
      }),
      backend.Depositer(ctc2, {
        ...stdlib.hasConsoleLogger,
        signal: () => {
          console.log("TOKEN DEPOSITED");
        },
      }),
      backend.Relay(ctc, {}),
    ]);
    await stdlib.wait(100);
    const getCurrentPrice = async () =>
      stdlib.formatCurrency((await ctc2.v.Auction.currentPrice())[1]);
    const getClosed = async () => (await ctc2.v.Auction.closed())[1] || false;

    let cp = await getCurrentPrice();
    console.log(`current price: ${cp}`);
    assert.equal(await getCurrentPrice(), 100);
    assert.equal(await getClosed(), false);
    assert.equal(Math.round(await getBalance(accAlice)), 1002);
    assert.equal(Math.round(await getBalance(accBob)), 998);
    assert.equal(
      stdlib.bigNumberToNumber(await stdlib.balanceOf(acc, gil.id)),
      0
    );
    console.log(`balance (acc): ${await getBalance(accAlice)}`);
    console.log(`balance (acc2): ${await getBalance(accBob)}`);
    console.log("acc accept offer");
    await ctc.a.Bid.acceptOffer();
    console.log(`balance (acc): ${await getBalance(accAlice)}`);
    console.log(`balance (acc2): ${await getBalance(accBob)}`);
    assert.equal(Math.round(await getBalance(accAlice)), 902);
    assert.equal(Math.round(await getBalance(accBob)), 1097);
    assert.equal(await getClosed(), true);
    assert.equal(
      stdlib.bigNumberToNumber(await stdlib.balanceOf(acc, gil.id)),
      1
    );
  })(accAlice, accBob);

  console.log("CAN PURCHASE AT END");
  await (async (acc, acc2) => {
    let addr = acc.networkAccount.addr;
    let ctc = acc.contract(backend);
    Promise.all([
      backend.Constructor(ctc, {
        getParams: () => getParams(addr),
        signal,
      }),
    ]);
    let appId = await ctc.getInfo();
    console.log(appId);
    let ctc2 = acc2.contract(backend, appId);
    Promise.all([
      backend.Contractee(ctc2, {}),
      backend.Auctioneer(ctc2, {
        ...stdlib.hasConsoleLogger,
        getParams: () => ({
          token: gil.id,
          addr: addr,
          addr2: addr,
          creator: addr,
          startPrice: stdlib.parseCurrency(100),
          floorPrice: stdlib.parseCurrency(1),
          endConsensusTime: 0,
        }),
        signal: () => {
          console.log("AUCTION CREATED");
        },
        close: () => {},
      }),
      backend.Depositer(ctc2, {
        ...stdlib.hasConsoleLogger,
        signal: () => {
          console.log("TOKEN DEPOSITED");
        },
      }),
      backend.Relay(ctc, {}),
    ]);
    await stdlib.wait(100);
    const getCurrentPrice = async () =>
      stdlib.formatCurrency((await ctc2.v.Auction.currentPrice())[1]);
    const getClosed = async () => (await ctc2.v.Auction.closed())[1] || false;

    let cp = await getCurrentPrice();
    console.log(`current price: ${cp}`);
    assert.equal(await getCurrentPrice(), 100);
    assert.equal(await getClosed(), false);
    assert.equal(
      stdlib.bigNumberToNumber(await stdlib.balanceOf(acc, gil.id)),
      1
    );
    console.log(`balance (acc): ${await getBalance(accAlice)}`);
    console.log(`balance (acc2): ${await getBalance(accBob)}`);
    while (cp > 1) {
      await ctc.a.Bid.touch();
      let last = cp;
      cp = await getCurrentPrice();
      if (last !== cp) {
        console.log(`current price: ${cp}`);
      }
    }
    console.log('acc accept offer')
    assert.equal(Math.round(await getBalance(accAlice)), 904);
    assert.equal(Math.round(await getBalance(accBob)), 1095);
    await ctc.a.Bid.acceptOffer();
    console.log(`balance (acc): ${await getBalance(accAlice)}`);
    console.log(`balance (acc2): ${await getBalance(accBob)}`);
    assert.equal(Math.round(await getBalance(accAlice)), 903);
    assert.equal(Math.round(await getBalance(accBob)), 1096);
    assert.equal(await getClosed(), true);
    assert.equal(
      stdlib.bigNumberToNumber(await stdlib.balanceOf(acc, gil.id)),
      2
    );
  })(accAlice, accBob);

  console.log("CAN PURCHASE IN MID");
  await (async (acc, acc2) => {
    let addr = acc.networkAccount.addr;
    let ctc = acc.contract(backend);
    Promise.all([
      backend.Constructor(ctc, {
        getParams: () => getParams(addr),
        signal,
      }),
    ]);
    let appId = await ctc.getInfo();
    console.log(appId);
    let ctc2 = acc2.contract(backend, appId);
    Promise.all([
      backend.Contractee(ctc2, {}),
      backend.Auctioneer(ctc2, {
        ...stdlib.hasConsoleLogger,
        getParams: () => ({
          token: gil.id,
          addr: addr,
          addr2: addr,
          creator: addr,
          startPrice: stdlib.parseCurrency(100),
          floorPrice: stdlib.parseCurrency(1),
          endConsensusTime: 0,
        }),
        signal: () => {
          console.log("AUCTION CREATED");
        },
        close: () => {},
      }),
      backend.Depositer(ctc2, {
        ...stdlib.hasConsoleLogger,
        signal: () => {
          console.log("TOKEN DEPOSITED");
        },
      }),
      backend.Relay(ctc, {}),
    ]);
    await stdlib.wait(100);
    const getCurrentPrice = async () =>
      stdlib.formatCurrency((await ctc2.v.Auction.currentPrice())[1]);
    const getClosed = async () => (await ctc2.v.Auction.closed())[1] || false;

    let cp = await getCurrentPrice();
    console.log(`current price: ${cp}`);
    assert.equal(await getCurrentPrice(), 100);
    assert.equal(await getClosed(), false);
    assert.equal(
      stdlib.bigNumberToNumber(await stdlib.balanceOf(acc, gil.id)),
      2
    );
    console.log(`balance (acc): ${await getBalance(accAlice)}`);
    console.log(`balance (acc2): ${await getBalance(accBob)}`);
    assert.equal(Math.round(await getBalance(accAlice)), 905);
    assert.equal(Math.round(await getBalance(accBob)), 1095);
    while (cp > 1) {
      await ctc.a.Bid.touch();
      if(Math.random()>.8) {
        console.log('acc accept offer')
        await ctc.a.Bid.acceptOffer();
      }
      let last = cp;
      cp = await getCurrentPrice();
      if (last !== cp) {
        console.log(`current price: ${cp}`);
      }
      let closed = await getClosed()
      if(closed) {
        break
      }
    }
    console.log(`balance (acc): ${await getBalance(accAlice)}`);
    console.log(`balance (acc2): ${await getBalance(accBob)}`);
    assert.equal(await getClosed(), true);
    assert.equal(
      stdlib.bigNumberToNumber(await stdlib.balanceOf(acc, gil.id)),
      3
    );
  })(accAlice, accBob);

  process.exit();
})();
