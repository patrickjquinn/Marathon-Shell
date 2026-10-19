use cxx_qt_build::CxxQtBuilder;

fn main() {
    CxxQtBuilder::new().file("src/network.rs").file("src/power.rs").build();
}
