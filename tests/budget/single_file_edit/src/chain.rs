pub fn target() -> i32 {
    first() + 1
}

pub fn first() -> i32 {
    let mut total = 0;
    for i in 0..64 {
        total += i * i - 3 * i + 7;
    }
    total + second()
}

pub fn second() -> i32 {
    let mut total = 0;
    for i in 0..32 {
        total += i * 5;
    }
    total
}

pub fn unrelated() -> i32 {
    let mut total = 0;
    for i in 0..16 {
        total -= i;
    }
    total
}
