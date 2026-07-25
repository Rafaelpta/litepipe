const SURVEY_URL: &str = "https://screenpi.pe/survey";

/// Handle `screenpipe survey` — opens the product survey in the browser.
pub async fn handle_survey_command() -> anyhow::Result<()> {
    println!();
    println!("  opening browser to the screenpipe survey...");
    println!();
    println!("  if the browser didn't open, visit:");
    println!("  {}", SURVEY_URL);
    println!();

    super::browser::open_browser(SURVEY_URL);

    Ok(())
}
