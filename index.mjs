import { loadStdlib } from "@reach-sh/stdlib";
import assert from "assert";

const [, , infile] = process.argv;

(async () => {
  console.log("START");

  const backend = await import(`./build/${infile}.main.mjs`);
  const stdlib = await loadStdlib();
  const startingBalance = stdlib.parseCurrency(2000);

  const accAlice = await stdlib.newTestAccount(startingBalance);
  const accBob = await stdlib.newTestAccount(startingBalance);
  const accEve = await stdlib.newTestAccount(startingBalance);
  const accs = await Promise.all(
    Array.from({ length: 10 }).map(() => stdlib.createAccount())
  );
  await stdlib.wait(10);

  const addr = accAlice.getAddress();

  const reset = async (accs) => {
    await Promise.all(accs.map(rebalance));
    await Promise.all(
      accs.map(async (el) =>
        console.log(`balance (acc): ${await getBalance(accAlice)}`)
      )
    );
  };

  const rebalance = async (acc) => {
    if ((await getBalance(acc)) > 2000) {
      await stdlib.transfer(
        acc,
        accEve.networkAccount.addr,
        stdlib.parseCurrency((await getBalance(acc)) - 2000)
      );
    } else {
      await stdlib.transfer(
        accEve,
        acc.networkAccount.addr,
        stdlib.parseCurrency(2000 - (await getBalance(acc)))
      );
    }
  };

  const zorkmid = await stdlib.launchToken(accAlice, "zorkmid", "ZMD");
  const gil = await stdlib.launchToken(accBob, "gil", "GIL");
  await accAlice.tokenAccept(gil.id);
  await accBob.tokenAccept(zorkmid.id);

  const getBalance = async (who) =>
    stdlib.formatCurrency(await stdlib.balanceOf(who), 4);

  const beforeAlice = await getBalance(accAlice);
  const beforeBob = await getBalance(accBob);

  const getParams = () => ({
    addr,
    amt: stdlib.parseCurrency(1),
  });

  const signal = () => {};

  // ---------------------------------------------

  // (1) can be deleted before activation
  console.log("CAN DELETED INACTIVE");
  (async (acc) => {
    let addr = acc.getAddress();
    let ctc = acc.contract(backend);
    Promise.all([
      backend.Constructor(ctc, {
        getParams,
        signal,
      }),
      backend.Verifier(ctc, {}),
    ]).catch(console.dir);
    let appId = stdlib.bigNumberToNumber(await ctc.getInfo()); // wait
    console.log({ appId });
  })(accAlice);
  await stdlib.wait(4);

  await reset([accAlice, accBob]);

  // ---------------------------------------------

  // (2) constructor receives payment on activation
  console.log("CAN ACTIVATE WITH PAYMENT");
  await (async (acc, acc2) => {
    let addr = acc.networkAccount.addr;
    let ctc = acc.contract(backend);
    Promise.all([
      backend.Constructor(ctc, {
        getParams,
        signal,
      }),
    ]);
    let appId = stdlib.bigNumberToNumber(await ctc.getInfo()); // wait
    console.log({ appId });
    let ctc2 = acc2.contract(backend, appId);
    Promise.all([backend.Contractee(ctc2, {})]);
    await stdlib.wait(4);
  })(accAlice, accBob);
  await stdlib.wait(20);

  const afterAlice = await getBalance(accAlice);
  const afterBob = await getBalance(accBob);

  const diffAlice = Math.round(afterAlice - beforeAlice);
  const diffBob = Math.round(afterBob - beforeBob);

  console.log(
    `Alice went from ${beforeAlice} to ${afterAlice} (${diffAlice}).`
  );
  console.log(`Bob went from ${beforeBob} to ${afterBob} (${diffBob}).`);

  //assert.equal(diffAlice, 1);
  //assert.equal(diffBob, -1);

  await reset([accAlice, accBob]);

  // ---------------------------------------------

  // (3) can purchase
  console.log("CAN PURCHASE AT START");
  await (async (acc, acc2) => {
    let addr = acc.getAddress();
    console.log({ addr });
    console.log(stdlib.formatAddress(addr));
    let ctc = acc.contract(backend);
    ctc.p.Constructor({ getParams, signal })
    let appId = stdlib.bigNumberToNumber(await ctc.getInfo()); // wait
    console.log({ appId });
    let ctc2 = acc2.contract(backend, parseInt(appId));
    ctc2.p.Contractee({});
    ctc2.p.Auctioneer({
      ...stdlib.hasConsoleLogger,
      getParams: async () => {
        const secs = await stdlib.getNetworkSecs()
        console.log({ secs });
        return {
          token: gil.id,
          addr: addr,
          addr2: addr,
          creator: addr,
          startPrice: 100, //stdlib.parseCurrency(100),
          floorPrice: 10, //stdlib.parseCurrency(10),
          endSecs: secs + 1000,
          addrs: Array.from({ length: 5 }).map((el) => addr),
          distr: Array.from({ length: 5 }).map((el) => 0),
          royaltyCap: 100,
        };
      },
      signal: () => {
        console.log("AUCTION CREATED");
      },
      close: () => {},
    });
    console.log("HERE")
    await  stdlib.wait(100);
    console.log(`balance (acc): ${await getBalance(accAlice)}`);
    console.log(`balance (acc2): ${await getBalance(accBob)}`);
    console.log("HERE")

    const getCurrentPrice = async (ctc) => {
      const cp = await ctc2.v.Auction.currentPrice();
      console.log(cp);
      return cp[0] === "Some" ? stdlib.formatCurrency(cp[1]) : 0;
    };
    const getClosed = async () => (await ctc2.v.Auction.closed())[1] || false;

    /*
    let cp = await getCurrentPrice();
    console.log(`current price: ${cp}`);
    assert.equal(await getCurrentPrice(), 100);
    assert.equal(await getClosed(), false);
    assert.equal(Math.round(await getBalance(accAlice)), 2001);
    assert.equal(Math.round(await getBalance(accBob)), 1999);
    assert.equal(
      stdlib.bigNumberToNumber(await stdlib.balanceOf(acc, gil.id)),
      0
    );
    console.log(`balance (acc): ${await getBalance(accAlice)}`);
    console.log(`balance (acc2): ${await getBalance(accBob)}`);
    console.log("acc accept offer");
    */
    for (let i = 0; i < 10; i++) {
      stdlib.wait(1000);
      console.log(i);
    }
    await ctc.a.Bid.acceptOffer().catch(console.dir);
    /*
    console.log(`balance (acc): ${await getBalance(accAlice)}`);
    console.log(`balance (acc2): ${await getBalance(accBob)}`);
    assert.equal(Math.round(await getBalance(accAlice)), 1901);
    assert.equal(Math.round(await getBalance(accBob)), 2099);
    assert.equal(await getClosed(), true);
    assert.equal(
      stdlib.bigNumberToNumber(await stdlib.balanceOf(acc, gil.id)),
      1
    );
    */
  })(accAlice, accBob);
  await stdlib.wait(4);
  await reset([accAlice, accBob]);

  console.log("CAN PURCHASE AT END");
  await (async (acc, acc2) => {
    let addr = acc.networkAccount.addr;
    let ctc = acc.contract(backend);
    Promise.all([
      backend.Constructor(ctc, {
        getParams,
        signal,
      }),
    ]);
    let appId = stdlib.bigNumberToNumber(await ctc.getInfo()); // wait
    console.log({ appId });
    let ctc2 = acc2.contract(backend, appId);
    Promise.all([
      backend.Contractee(ctc2, {}),
      backend.Auctioneer(ctc2, {
        ...stdlib.hasConsoleLogger,
        getParams: async () => {
          const secs = stdlib.bigNumberToNumber(await stdlib.getNetworkSecs());
          return {
            token: gil.id,
            addr: addr,
            addr2: addr,
            creator: addr,
            startPrice: stdlib.parseCurrency(100),
            floorPrice: stdlib.parseCurrency(1),
            endSecs: secs + 1000,
            addrs: Array.from({ length: 5 }).map((el) => addr),
            distr: Array.from({ length: 5 }).map((el) => 0),
            royaltyCap: 10,
          };
        },
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
    ]);
    await stdlib.wait(100);
    /*
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
    */
    let cp = 100000;
    while (cp > 1) {
      await ctc.a.Bid.touch();
      let last = cp;
      cp = await getCurrentPrice();
      console.log(cp);
      if (last !== cp) {
        console.log(`current price: ${cp}`);
      }
    }
    /*
    console.log("acc accept offer");
    assert.equal(Math.round(await getBalance(accAlice)), 2001);
    assert.equal(Math.round(await getBalance(accBob)), 1999);
    */
    await ctc.a.Bid.acceptOffer();
    /*
    console.log(`balance (acc): ${await getBalance(accAlice)}`);
    console.log(`balance (acc2): ${await getBalance(accBob)}`);
    assert.equal(Math.round(await getBalance(accAlice)), 2000);
    assert.equal(Math.round(await getBalance(accBob)), 2000);
    assert.equal(await getClosed(), true);
    assert.equal(
      stdlib.bigNumberToNumber(await stdlib.balanceOf(acc, gil.id)),
      2
    );
    */
  })(accAlice, accBob);
  await stdlib.wait(4);
  await reset([accAlice, accBob]);

  console.log("CAN PURCHASE IN MID");
  await (async (acc, acc2) => {
    let addr = acc.networkAccount.addr;
    let ctc = acc.contract(backend);
    Promise.all([
      backend.Constructor(ctc, {
        getParams,
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
        getParams: async () => {
          const secs = stdlib.bigNumberToNumber(await stdlib.getNetworkSecs());
          return {
            token: gil.id,
            addr: addr,
            addr2: addr,
            creator: addr,
            startPrice: stdlib.parseCurrency(100),
            floorPrice: stdlib.parseCurrency(10),
            endSecs: secs + 1000,
            addrs: Array.from({ length: 5 }).map((el) => addr),
            distr: Array.from({ length: 5 }).map((el) => 0),
            royaltyCap: 100,
          };
        },
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
    assert.equal(Math.round(await getBalance(accAlice)), 2001);
    assert.equal(Math.round(await getBalance(accBob)), 1999);
    while (cp > 1) {
      await ctc.a.Bid.touch();
      if (Math.random() > 0.8) {
        console.log("acc accept offer");
        await ctc.a.Bid.acceptOffer();
      }
      let last = cp;
      cp = await getCurrentPrice();
      if (last !== cp) {
        console.log(`current price: ${cp}`);
      }
      let closed = await getClosed();
      if (closed) {
        break;
      }
    }
    console.log(`balance (acc): ${await getBalance(accAlice)}`);
    console.log(`balance (acc2): ${await getBalance(accBob)}`);
    assert.equal(
      stdlib.bigNumberToNumber(await stdlib.balanceOf(acc, gil.id)),
      3
    );
  })(accAlice, accBob);
  await stdlib.wait(4);
  await reset([accAlice, accBob]);

  console.log("CAN CANCEL");
  await (async (acc, acc2) => {
    let addr = acc.networkAccount.addr;
    let ctc = acc.contract(backend);
    Promise.all([
      backend.Constructor(ctc, {
        getParams,
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
        getParams: async () => {
          const secs = stdlib.bigNumberToNumber(await stdlib.getNetworkSecs());
          return {
            token: gil.id,
            addr: addr,
            addr2: addr,
            creator: addr,
            startPrice: stdlib.parseCurrency(100),
            floorPrice: stdlib.parseCurrency(10),
            endSecs: secs + 1000,
            addrs: Array.from({ length: 5 }).map((el) => addr),
            distr: Array.from({ length: 5 }).map((el) => 0),
            royaltyCap: 100,
          };
        },
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
      stdlib.bigNumberToNumber(await stdlib.balanceOf(acc2, gil.id)),
      2
    );
    console.log(stdlib.bigNumberToNumber(await stdlib.balanceOf(acc2, gil.id)));
    await ctc.a.Bid.cancel()
      .then(() => console.log("Cancelled by Alice"))
      .catch(console.log);
    await ctc2.a.Bid.cancel()
      .then(() => console.log("Cancelled by Bob"))
      .catch(console.log);
    console.log(stdlib.bigNumberToNumber(await stdlib.balanceOf(acc2, gil.id)));
    assert.equal(
      stdlib.bigNumberToNumber(await stdlib.balanceOf(acc2, gil.id)),
      3
    );
    console.log(`balance (acc): ${await getBalance(accAlice)}`);
    console.log(`balance (acc2): ${await getBalance(accBob)}`);
    assert.equal(Math.round(await getBalance(accAlice)), 1999);
    assert.equal(Math.round(await getBalance(accBob)), 2001);
  })(accBob, accAlice); // switch to prevent bignumber to number overflow
  await stdlib.wait(4);
  await reset([accAlice, accBob]);

  // TODO add test for end secs timing
  // TODO add test for payouts

  console.log("CAN SPLIT PAYMENT");
  function getRandomInt(max) {
    return Math.floor(Math.random() * max);
  }
  try {
    let program = [
      {
        start: 2000,
        floor: 1,
        distr: Array.from({ length: 5 }).map(() => getRandomInt(2)),
      },
      {
        start: 2000,
        floor: getRandomInt(10) + 5,
        distr: Array.from({ length: 5 }).map(() => getRandomInt(5)),
      },
      {
        start: 2000,
        floor: getRandomInt(100) + 50,
        distr: Array.from({ length: 5 }).map(() => getRandomInt(50)),
      },
      {
        start: 2000,
        floor: getRandomInt(1000) + 500,
        distr: Array.from({ length: 5 }).map(() => getRandomInt(500)),
      },
    ];
    for (let i = 0; i < 4; i++) {
      let { start, floor, distr } = program[i];
      console.log({
        start,
        floor,
        distr,
        distrSum: distr.reduce((acc, val) => acc + val, 0),
      });
      await (async (acc, acc2) => {
        let addr = acc.networkAccount.addr;
        let ctc = acc.contract(backend);
        Promise.all([
          backend.Constructor(ctc, {
            getParams,
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
            getParams: async () => {
              const secs = stdlib.bigNumberToNumber(
                await stdlib.getNetworkSecs()
              );
              return {
                token: gil.id,
                addr: addr,
                addr2: addr,
                creator: addr,
                startPrice: stdlib.parseCurrency(start),
                floorPrice: stdlib.parseCurrency(floor),
                endSecs: secs + 2500,
                addrs: accs.slice(0, 5).map((el) => el.networkAccount.addr),
                distr,
                royaltyCap: floor * 10,
              };
            },
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
        ]);
        await stdlib.wait(100);
        const getCurrentPrice = async () =>
          stdlib.formatCurrency((await ctc2.v.Auction.currentPrice())[1]);

        let cp = await getCurrentPrice();
        console.log(`current price: ${cp}`);
        console.log(`balance (acc): ${await getBalance(accAlice)}`);
        console.log(`balance (acc2): ${await getBalance(accBob)}`);
        while (cp > floor) {
          await ctc.a.Bid.touch();
          let last = cp;
          cp = await getCurrentPrice();
          console.log(cp);
          if (last !== cp) {
            console.log(`current price: ${cp}`);
          }
        }
        stdlib.wait(10);
        console.log("acc accept offer");
        await ctc.a.Bid.acceptOffer();
        console.log(`balance (acc): ${await getBalance(accAlice)}`);
        console.log(`balance (acc2): ${await getBalance(accBob)}`);
        await backend.Relay(ctc, {});

        for (let i = 0; i < 10; i++) {
          console.log(
            `balance (accs[${i}]): ${stdlib.formatCurrency(
              await stdlib.balanceOf(accs[i]),
              6
            )}`
          );
        }
      })(accAlice, accBob);
    }
  } catch (e) {
    console.log(e);
  }

  await stdlib.wait(100);
  //await reset([accAlice, accBob]);

  process.exit();
})();
