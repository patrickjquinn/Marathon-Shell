use cxx_qt_build::CxxQtBuilder;

fn main() {
    CxxQtBuilder::new().file("src/identity.rs").file("src/network.rs").file("src/power.rs").build();
}
