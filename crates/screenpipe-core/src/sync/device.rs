/// Get or create a persistent machine ID.
///
/// Reads from `~/.screenpipe/machine_id` if it exists.
/// Otherwise generates a UUID v4, writes it to that file, and returns it.
pub fn get_or_create_machine_id() -> String {
    let machine_id_path = crate::paths::default_screenpipe_data_dir().join("machine_id");

    if let Ok(id) = std::fs::read_to_string(&machine_id_path) {
        let id = id.trim().to_string();
        if !id.is_empty() {
            return id;
        }
    }

    let id = uuid::Uuid::new_v4().to_string();
    let _ = std::fs::create_dir_all(machine_id_path.parent().unwrap());
    let _ = std::fs::write(&machine_id_path, &id);
    id
}
