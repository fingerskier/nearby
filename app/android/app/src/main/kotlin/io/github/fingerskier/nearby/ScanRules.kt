package io.github.fingerskier.nearby

/**
 * Android ignores an app's scan starts once it has made five in the last 30 s: it logs "scanning too
 * frequently" and delivers nothing. Starts are spaced to stay one under that.
 */
class StartLimiter(
    private val limit: Int = 4,
    private val windowMs: Long = 30_000,
    private val marginMs: Long = 1_000,
) {
    private val starts = ArrayDeque<Long>()

    /** How long a start at [now] (ms, monotonic) has to wait; 0 means it can go ahead. */
    fun delayAt(now: Long): Long {
        while (starts.isNotEmpty() && now - starts.first() >= windowMs) starts.removeFirst()
        return if (starts.size < limit) 0 else starts.first() + windowMs + marginMs - now
    }

    fun record(now: Long) {
        starts.addLast(now)
    }
}

/** BluetoothDevice.getAddressType() (API 35+) as BlueZ names it; null when Android doesn't know. */
fun addressTypeName(type: Int): String? = when (type) {
    0 -> "public"
    1 -> "random"
    else -> null
}

/** ScanCallback.onScanFailed codes. */
fun scanErrorName(code: Int): String = when (code) {
    1 -> "already started"
    2 -> "the app couldn't register with the Bluetooth stack"
    3 -> "internal Bluetooth error"
    4 -> "this phone doesn't support the scan settings"
    5 -> "out of Bluetooth hardware resources"
    6 -> "scanning too frequently"
    else -> "error $code"
}

/** The Bluetooth SIG base UUID with a 16-bit UUID filled in. */
fun uuid16(short: Int): String = "0000%04x-0000-1000-8000-00805f9b34fb".format(short)

/**
 * Android pauses unfiltered scans while the screen is off, so screen-off scans match the advertisers people
 * actually carry instead. Bluetooth SIG company identifiers.
 */
val screenOffCompanies = intArrayOf(
    0x004C, // Apple: iPhones, AirPods, AirTags, Watches
    0x0075, // Samsung: Galaxy phones, Buds, SmartTags
    0x00E0, // Google
    0x0006, // Microsoft: Swift Pair
    0x0087, // Garmin
    0x027D, // Huawei
    0x038F, // Xiaomi
    0x0157, // Huami (Amazfit, Mi Band)
    0x012D, // Sony
    0x009E, // Bose
    0x0171, // Amazon
    0x0059, // Nordic Semiconductor, inside many small gadgets
    0x02E5, // Espressif, inside many small gadgets
)

/** 16-bit UUIDs that trackers and phones put in service data. */
val screenOffServiceData = intArrayOf(
    0xFE2C, // Google Fast Pair
    0xFEAA, // Eddystone, and Google's Find My Device network
    0xFD5A, // Samsung SmartTag
    0xFEED, // Tile
    0xFEEC, // Tile
    0xFE95, // Xiaomi
    0xFD6F, // exposure notifications
    0xFE9F, // Google
)
