"reach 0.1";
"use strict";

// -----------------------------------------------
// Name: ALGO/ETH/CFX NFT Jam Reverse Auction
// Author: Nicholas Shellabarger
// Version: 0.5.0 - use single view
// Requires Reach v0.1.7
// -----------------------------------------------

import { min, max } from "@nash-protocol/starter-kit#lite-v0.1.9r1:util.rsh";

const SERIAL_VER = 0; // serial version of reach app reserved to release identical contracts under a separate plana id
// regarding plan ids, the plan ids is the md5 of the approval program in algorand

const DIST_LENGTH = 10; // number of slots to distribute proceeds after sale
//const PLATFORM_AMT = 1000000; // 1A

const FEE_MIN_ACCEPT = 7000;
const FEE_MIN_CONSTRUCT = 5000;
const FEE_MIN_RELAY = 17000;

// FUNCS

/*
 * precision used in fixed point arithmetic
 */
const precision = 1000000; // 10 ^ 6

/*
 * calculate price based on seconds elapsed since reference secs
 */
const priceFunc = (startPrice, floorPrice, referenceConcensusSecs, dk) =>
  max(
    floorPrice,
    ((diff) => {
      if (startPrice <= diff) {
        // if is lazy, ? is not lazy (startPrice - diff can underflow)
        return floorPrice;
      } else {
        return startPrice - diff;
      }
    })(
      min(
        ((lastConsensusSecs() - referenceConcensusSecs) * dk) / precision,
        startPrice - floorPrice
      )
    )
  );

// calculate slope of line to determine price
const calc = (d, d2, p) => {
  const fD = fx(6)(Pos, d);
  const fD2 = fx(6)(Pos, d2);
  return fxdiv(fD, fD2, p);
};

// INTERACTS

const relayInteract = {};

const auctioneerInteract = {
  getParams: Fun(
    [],
    Object({
      tokenAmount: UInt, // NFT token amount
      startPrice: UInt, // 100
      floorPrice: UInt, // 1
      endSecs: UInt, // 1
      addrs: Array(Address, DIST_LENGTH), // [addr, addr, addr, addr, addr, addr, addr, addr, addr, addr]
      distr: Array(UInt, DIST_LENGTH), // [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
      royaltyCap: UInt, // 10
      acceptFee: UInt, // 0.008
      constructFee: UInt, // 0.006
      relayFee: UInt, // 0.007
    })
  ),
  signal: Fun([], Null),
};

export const Event = () => [];

export const Participants = () => [
  Participant("Auctioneer", auctioneerInteract),
  ParticipantClass("Relay", relayInteract),
];

const State = Tuple(
  /*maanger*/ Address,
  /*token*/ Token,
  /*tokenAmount*/ UInt,
  /*currentPrice*/ UInt,
  /*startPrice*/ UInt,
  /*floorPrice*/ UInt,
  /*closed*/ Bool,
  /*endSecs*/ UInt,
  /*priceChangePerSec*/ UInt,
  /*addrs*/ Array(Address, DIST_LENGTH), // [addr, addr, addr, addr, addr, addr, addr, addr, addr, addr]
  /*distr*/ Array(UInt, DIST_LENGTH), // [0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  /*royaltyCap*/ UInt
);

const STATE_CURRENT_PRICE = 3;
const STATE_CLOSED = 6;

export const Views = () => [
  View({
    state: State,
  }),
];

export const Api = () => [
  API({
    touch: Fun([], Null),
    acceptOffer: Fun([], Null),
    cancel: Fun([], Null),
  }),
];

export const App = (map) => {
  const [
    { amt, ttl, tok0: token },
    [addr, _],
    [Auctioneer, Relay],
    [v],
    [a],
    _,
  ] = map;
  Auctioneer.only(() => {
    const manager = this;
    const {
      tokenAmount,
      startPrice,
      floorPrice,
      endSecs,
      addrs,
      distr,
      royaltyCap,
      acceptFee,
      constructFee,
      relayFee,
    } = declassify(interact.getParams());
  });
  Auctioneer.publish(
    manager,
    tokenAmount,
    startPrice,
    floorPrice,
    endSecs,
    addrs,
    distr,
    royaltyCap,
    acceptFee,
    constructFee,
    relayFee
  )
    .check(() => {
      check(tokenAmount > 0);
      check(floorPrice > 0);
      check(floorPrice <= startPrice); // fp < sp => auction, fp == sp => sale
      check(endSecs > 0);
      // no checks for addrs
      check(distr.sum() <= royaltyCap);
      check(royaltyCap == (10 * floorPrice) / 1000000);
      check(acceptFee >= FEE_MIN_ACCEPT);
      check(constructFee >= FEE_MIN_CONSTRUCT);
      check(relayFee >= FEE_MIN_RELAY);
    })
    .pay([
      amt + (constructFee + acceptFee + relayFee) + SERIAL_VER,
      [tokenAmount, token],
    ])
    .timeout(relativeTime(ttl), () => {
      Anybody.publish();
      commit();
      exit();
    });
  transfer(amt + constructFee + SERIAL_VER).to(addr);

  Auctioneer.interact.signal();
  const referenceConcensusSecs = lastConsensusSecs();
  const dk = calc(
    startPrice - floorPrice,
    endSecs - referenceConcensusSecs,
    precision
  ).i.i;

  const initialState = [
    /*maanger*/ manager,
    /*token*/ token,
    /*tokenAmount*/ tokenAmount,
    /*currentPrice*/ startPrice,
    /*startPrice*/ startPrice,
    /*floorPrice*/ floorPrice,
    /*closed*/ false,
    /*endSecs*/ endSecs,
    /*priceChangePerSec*/ dk / precision,
    /*addrs*/ addrs,
    /*distr*/ distr,
    /*royaltyCap*/ royaltyCap,
  ];

  // TODO revise invariant to eliminate assume/require
  // JAY The reason you need the assume/require is because of the loop invariant.
  // JAY You should put implies(!done, balance(token) == tokenAmount) in the invariant and remove the assume/requires in the apis
  // JAY You should do something like implies(done, balance(token) == 0) in the variant also

  const [state, whoami] = parallelReduce([initialState, Auctioneer])
    .define(() => {
      v.state.set(state);
    })
    .invariant(
      implies(!state[STATE_CLOSED], balance(token) == tokenAmount) &&
        balance() >= acceptFee + relayFee /*+ rest in case of sale*/ //&&
      //balance(token) <= tokenAmount
    )
    .while(!state[STATE_CLOSED])
    // TODO may use api_ later in future version of reach
    // api: updates current price
    .api(
      a.touch,
      () => assume(state[STATE_CURRENT_PRICE] >= floorPrice),
      () => 0,
      (k) => {
        require(state[STATE_CURRENT_PRICE] >= floorPrice);
        k(null);
        const newPrice = priceFunc(
          startPrice,
          floorPrice,
          referenceConcensusSecs,
          dk
        );
        return [Tuple.set(state, STATE_CURRENT_PRICE, newPrice), this];
      }
    )
    // api: accepts offer
    .api(
      a.acceptOffer,
      //() => assume(balance(token) == tokenAmount),
      () => assume(true),
      () => state[STATE_CURRENT_PRICE],
      (k) => {
        //require(balance(token) == tokenAmount);
        require(true);
        k(null);
        const cent = state[STATE_CURRENT_PRICE] / 100;
        const partTake = (state[STATE_CURRENT_PRICE] - cent) / royaltyCap;
        const distrTake = distr.slice(0, DIST_LENGTH).sum();
        const sellerTake =
          state[STATE_CURRENT_PRICE] - cent - partTake * distrTake;
        transfer(cent).to(addr);
        transfer(partTake * distr[0]).to(addrs[0]);
        transfer(sellerTake).to(Auctioneer);
        transfer([[balance(token), token]]).to(this);
        return [Tuple.set(state, STATE_CLOSED, true), this];
      }
    )
    // api: cancels auction
    .api(
      a.cancel,
      //() => assume(this === Auctioneer && balance(token) == tokenAmount),
      () => assume(this === Auctioneer),
      () => 0,
      (k) => {
        require(this === Auctioneer);
        //require(balance(token) == tokenAmount);
        k(null);
        transfer([0, [tokenAmount, token]]).to(this);
        return [
          Tuple.set(
            Tuple.set(state, STATE_CURRENT_PRICE, 0),
            STATE_CLOSED,
            true
          ),
          this,
        ];
      }
    )
    .timeout(false);
  transfer(acceptFee).to(whoami);
  commit();

  // REM know token balance is zero
  // REM Auction over
  // REM Relay races to reward while distributing proceeds
  // REM have assume/require here to fix token balance on exit without transfer
  Relay.only(() => {
    assume(balance(token) == 0);
  });
  Relay.publish();
  require(balance(token) == 0);

  const cent = state[STATE_CURRENT_PRICE] / 100;
  const partTake = (state[STATE_CURRENT_PRICE] - cent) / royaltyCap;
  const distrTake = distr.slice(1, DIST_LENGTH - 1).sum();
  const recvAmount = balance() - partTake * distrTake; // REM includes relayFee
  transfer(partTake * distr[1]).to(addrs[1]);
  transfer(partTake * distr[2]).to(addrs[2]);
  transfer(partTake * distr[3]).to(addrs[3]);
  transfer(partTake * distr[4]).to(addrs[4]);
  commit();
  Relay.publish();
  transfer(partTake * distr[5]).to(addrs[5]);
  transfer(partTake * distr[6]).to(addrs[6]);
  transfer(partTake * distr[7]).to(addrs[7]);
  transfer(partTake * distr[8]).to(addrs[8]);
  commit();
  Relay.only(() => {
    const rAddr = this;
  });
  Relay.publish(rAddr);
  transfer(partTake * distr[9]).to(addrs[9]);
  // REM If DIST_LENGTH > 10
  //WARNING: Compiler instructed to emit for Algorand, but we can statically determine that this program will not work on Algorand, because:
  // * Step 1 uses 1081 bytes of logs, but the limit is 1024. Step 1 starts at /app/interface.rsh:182:14:dot.
  transfer(recvAmount).to(rAddr);
  commit();
  exit();
};
// -----------------------------------------------
