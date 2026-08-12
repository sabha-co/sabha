// Client mirror of lib/otp_code.rb — keep the two in lockstep so what the user
// types into the six-cell field is normalized exactly the way the server will
// normalize it on submit (uppercase, correct the ambiguous O/I/L typos, then
// drop anything outside the alphabet). The alphabet itself excludes O, I and L.
export const ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
export const CODE_LENGTH = 6

const SUBSTITUTIONS = { O: "0", I: "1", L: "1" }

export function sanitize(input) {
  return Array.from(String(input ?? "").toUpperCase())
    .map((char) => SUBSTITUTIONS[char] ?? char)
    .filter((char) => ALPHABET.includes(char))
    .join("")
}
