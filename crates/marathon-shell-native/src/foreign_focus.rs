//! Whether a window mapped behind the current foreign front window needs a
//! fresh keyboard enter. The compositor owns the surfaces and performs the enter.

#[cxx_qt::bridge]
mod ffi {
    #[namespace = "marathon::foreign_focus"]
    extern "Rust" {
        fn should_reenter_front(
            same_surface: bool,
            same_client: bool,
            front_is_foreign: bool,
            same_app_id: bool,
        ) -> bool;
    }
}

fn should_reenter_front(
    same_surface: bool,
    same_client: bool,
    front_is_foreign: bool,
    same_app_id: bool,
) -> bool {
    !same_surface && same_client && front_is_foreign && !same_app_id
}

#[cfg(test)]
mod tests {
    use super::should_reenter_front;

    #[test]
    fn only_a_different_app_of_the_foreign_front_client_reenters() {
        for same_surface in [false, true] {
            for same_client in [false, true] {
                for front_is_foreign in [false, true] {
                    for same_app_id in [false, true] {
                        assert_eq!(
                            should_reenter_front(
                                same_surface,
                                same_client,
                                front_is_foreign,
                                same_app_id,
                            ),
                            (same_surface, same_client, front_is_foreign, same_app_id)
                                == (false, true, true, false),
                            "same_surface={same_surface} same_client={same_client} front_is_foreign={front_is_foreign} same_app_id={same_app_id}"
                        );
                    }
                }
            }
        }
    }
}
