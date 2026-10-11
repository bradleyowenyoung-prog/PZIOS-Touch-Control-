// StikDebug script for ZomIOS (patched OpenJDK, MirrorMappedCodeCache).
// Protocol: the JVM executes `brk #0x69` with x0 = bytes wanted and expects the address of a
// debugger-allocated RX region back in x0. We allocate it, make it TXM-executable, set x0, skip the brk.
const EXPECTED_REQUESTS = 1;   // exec reserves the JVM makes (code cache). Detach after this many.

function leHexToNum(hex) {
    let n = 0n;
    for (let i = 7; i >= 0; i--) n = (n << 8n) | BigInt(parseInt(hex.substr(i * 2, 2), 16));
    return n;
}
function numToLeHex(n) {
    let s = '';
    for (let i = 0; i < 8; i++) { s += Number(n & 0xFFn).toString(16).padStart(2, '0'); n >>= 8n; }
    return s;
}
function leHexToU32(hex) { return parseInt(hex.match(/../g).reverse().join(''), 16); }
function reg(resp, name) {
    const m = new RegExp(name + ':([0-9a-f]{16});').exec(resp);
    return m ? leHexToNum(m[1]) : null;
}

const pid = get_pid();
log(`pid = ${pid}`);
log(`attach_response = ${send_command(`vAttach;${pid.toString(16)}`)}`);

let handled = 0, total = 0;
while (handled < EXPECTED_REQUESTS) {
    total++;
    const resp = send_command('c');
    log(`stop ${total}: ${resp}`);
    const tidM = /T[0-9a-f]+thread:([0-9a-f]+);/.exec(resp);
    const sigM = /^T([0-9a-f]{2})/.exec(resp);
    if (!tidM || !sigM) { log('could not parse stop reply'); continue; }
    const tid = tidM[1];
    const pc = reg(resp, '20');
    const x0 = reg(resp, '00');
    if (pc === null || x0 === null) { log('missing registers'); send_command(`vCont;S${sigM[1]}:${tid}`); continue; }

    const insn = leHexToU32(send_command(`m${pc.toString(16)},4`));
    const isBrk = ((insn & 0xFFE0001F) >>> 0) === 0xD4200000;
    const imm = (insn >> 5) & 0xFFFF;
    if (!isBrk || imm !== 0x69) {
        log(`not brk #0x69 (insn 0x${insn.toString(16)}); forwarding signal 0x${sigM[1]}`);
        send_command(`vCont;S${sigM[1]}:${tid}`);
        continue;
    }

    const bytes = x0;
    const alloc = send_command(`_M${bytes.toString(16)},rx`);
    log(`alloc(${bytes} bytes) = ${alloc}`);
    if (!alloc || alloc.length === 0) { log('RX allocation failed; returning NULL to JVM'); send_command(`P0=0000000000000000;thread:${tid};`); }
    else {
        const addr = BigInt(`0x${alloc}`);
        log(`prepare_memory_region = ${prepare_memory_region(addr, bytes)}`);
        log(`set x0 = ${send_command(`P0=${numToLeHex(addr)};thread:${tid};`)}`);
    }
    log(`pc+4 = ${send_command(`P20=${numToLeHex(pc + 4n)};thread:${tid};`)}`);
    handled++;
}
log(`detach = ${send_command('D')}`);
