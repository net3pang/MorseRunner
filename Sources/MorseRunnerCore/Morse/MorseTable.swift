// Port of MorseTbl.pas — the Morse code table.
// Format per entry: '<char>[<code>]<freq>' where freq is the usage frequency
// in permille (vestigial; not used by the keyer) and <code> is the dit/dash
// representation. Procedural signs (sk, ar, kn, cq, bk, dx) have lowercase keys.

enum MorseTable {
    static let entries: [(char: Character, code: String)] = [
        ("1", ".----"), ("2", "..---"), ("3", "...--"), ("4", "....-"),
        ("5", "....."), ("6", "-...."), ("7", "--..."), ("8", "---.."),
        ("9", "----."), ("0", "-----"),
        ("A", ".-"), ("B", "-..."), ("C", "-.-."), ("D", "-.."), ("E", "."),
        ("F", "..-."), ("G", "--."), ("H", "...."), ("I", ".."), ("J", ".---"),
        ("K", "-.-"), ("L", ".-.."), ("M", "--"), ("N", "-."), ("O", "---"),
        ("P", ".--."), ("Q", "--.-"), ("R", ".-."), ("S", "..."), ("T", "-"),
        ("U", "..-"), ("V", "...-"), ("W", ".--"), ("X", "-..-"), ("Y", "-.--"),
        ("Z", "--.."),
        ("/", "-..-."), (".", ".-.-.-"), (",", "--..--"), ("?", "..--.."),
        ("=", "-...-"), ("\\", "...-."),
        ("s", "...-.-"), ("a", ".-.-."), ("k", "-.--."), ("c", "-.-.--.-"),
        ("b", "-...-.-"), ("d", "-..-..-"),
    ]
}
