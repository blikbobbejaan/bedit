struct Counter {
    count: u32,
}

impl Counter {
    fn bump(&mut self, by: u32) -> u32 {
        self.count += by;
        self.count
    }
}

fn add(left: i32, right: i32) -> i32 {
    left + right
}

fn main() {
    let total = add(1, 2);
    let mut counter = Counter { count: 0 };
    let bumped = counter.bump(3);
    println!("total {total} bumped {bumped}");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn adds() {
        assert_eq!(add(2, 2), 4);
    }
}
