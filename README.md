# 📘 AMBA AXI4 UVM Verification IP

## 🔹 Overview
This project implements a **UVM-based Verification IP (VIP)** for the **AMBA AXI4 protocol**, targeting protocol-correct, high-concurrency verification of AXI-compliant designs.

The environment is built to model **cycle-accurate AXI behavior**, including:
- Multiple outstanding transactions  
- Out-of-order completion  
- Parallel read/write channels  
- Burst-based transfers  
- Backpressure and timing variability  

The focus is on **architectural correctness, concurrency handling, and protocol fidelity**, reflecting real-world pre-silicon verification challenges.

---

# 🔹 What is AXI4?

## AXI Fundamentals
**AXI (Advanced eXtensible Interface)** is a high-performance, memory-mapped protocol defined under the AMBA specification.

It is widely used in SoC interconnects due to:
- High bandwidth
- Low latency
- Independent channel operation
- Support for multiple outstanding transactions

---

## AXI Channel Architecture

AXI consists of **five independent channels**:

| Channel | Direction | Purpose |
|--------|----------|--------|
| AW     | Master → Slave | Write address |
| W      | Master → Slave | Write data |
| B      | Slave → Master | Write response |
| AR     | Master → Slave | Read address |
| R      | Slave → Master | Read data |

### Key Property
All channels are **decoupled**, meaning:
- Address and data phases operate independently  
- Read and write paths run in parallel  
- Transactions can overlap in time  

---

## AXI Transaction Model

Each transaction is tagged with an **ID**, enabling:
- Multiple outstanding requests  
- Out-of-order completion  
- Independent tracking of transactions  

### Burst Types
- **FIXED** – Address remains constant  
- **INCR** – Address increments sequentially  
- **WRAP** – Address wraps around a boundary  

---

# 🔹 Project Implementation

## 1. Master Driver Architecture (Parallel Pipelines)

The master driver is implemented using **fully decoupled pipeline stages**:

### Write Channel
- **AW Stage** – Issues write addresses  
- **W Stage** – Drives write data bursts  
- **B Stage** – Handles write responses  

### Read Channel
- **AR Stage** – Issues read addresses  
- **R Stage** – Handles read data  

Each stage runs in an independent thread and communicates via **mailboxes**, enabling:

- Overlap of address, data, and response phases  
- True multiple outstanding transactions  
- Non-blocking transaction flow  

---

## 2. ID Management and Reuse Protection

AXI requires that an ID cannot be reused until its transaction completes.

### Implemented Mechanism

#### Sequence Side
- Free ID selection via `get_free_wr_id()` / `get_free_rd_id()`
- Semaphore-protected access to shared state

#### Driver Side
- Tracks in-flight IDs using arrays
- Synchronizes using semaphores
- Clears IDs on:
  - Write completion (`BRESP`)
  - Read completion (`RLAST`)

### Outcome
- Prevents protocol violations  
- Enables safe high-concurrency traffic  

---

## 3. Burst Generation (Protocol-Accurate)

Burst behavior is implemented in `post_randomize()`:

- Address progression logic per burst type  
- Byte-lane (`WSTRB`) generation  
- Alignment and boundary handling  
- Wrap boundary computation  

This ensures **cycle-accurate compliance with AXI burst semantics**.

---

## 4. Slave Driver with Memory Model

The slave driver models a **byte-addressed memory system**:

- Stores data in `smem`  
- Handles full AXI write and read flows  
- Supports randomized backpressure:
  - `AWREADY`, `WREADY`, `ARREADY`

### Robustness Feature
- Uses **4-state safe comparisons (`=== 1`)**  
- Prevents spurious transactions due to X-propagation  

---

## 5. Read Channel Concurrency Handling

### Problem
Concurrent read handling introduced:
- Missing beats  
- Incorrect data counts  
- Signal contention  

### Solution
- **Semaphore-based serialization** of R channel in both master and slave drivers  
- Ensures only one thread drives shared signals at a time  

### Result
- Correct beat counts  
- Stable handshake behavior  
- Support for multiple outstanding reads  

---

## 6. Monitor Design (Race-Free, OOO Safe)

### Features
- Separate analysis ports:
  - Write (`analysis_port_wr`)
  - Read (`analysis_port_rd`)
- ID-based transaction tracking  
- **Fork-per-read architecture**:
  - Each read transaction spawns an independent data collector  

### Benefit
- Eliminates AR → R race conditions  
- Supports out-of-order completion  
- Ensures accurate transaction reconstruction  

---

## 7. Scoreboard Architecture

The scoreboard verifies correctness using **dual FIFO matching**:

- Write path: `m_wr_fifo` ↔ `s_wr_fifo`  
- Read path:  `m_rd_fifo` ↔ `s_rd_fifo`  

### Features
- Transaction comparison  
- Data integrity checks  
- Timeout watchdog  

### Functional Coverage
- Burst type × size × length  
- WSTRB patterns  

---

# 🔹 Verification Scenarios Implemented

The environment validates the following AXI behaviors:

## Basic Transactions
- Single write transaction  
- Single read transaction  

## Burst Transactions
- FIXED burst transfers  
- INCR burst transfers  
- WRAP burst transfers  

## Concurrency Scenarios
- Multiple outstanding write transactions  
- Multiple outstanding read transactions  

These scenarios stress:
- Channel decoupling  
- ID reuse correctness  
- Burst handling logic  
- Backpressure resilience  

---

# 🔹 Testcases

| Testcase | Description |
|--------|------------|
| `single_write_test` | Verifies single write transaction |
| `single_read_test` | Verifies single read transaction |
| `fixed_burst_test` | Verifies FIXED burst behavior |
| `incr_burst_test` | Verifies INCR burst behavior |
| `wrap_burst_test` | Verifies WRAP burst behavior |
| `outstanding_write_test` | Verifies multiple concurrent writes |
| `outstanding_read_test` | Verifies multiple concurrent reads |

A regression sequence executes all scenarios to validate full protocol coverage.

---

# 🔹 Summary

This project demonstrates a **comprehensive AXI4 verification environment** with:

- Parallel channel modeling  
- Accurate burst behavior  
- Robust ID management  
- Race-free monitoring  
- Concurrency-safe driver design  

It captures key challenges in AXI verification, including:
- Timing-dependent race conditions  
- Signal contention in concurrent flows  
- Protocol correctness under high traffic  
