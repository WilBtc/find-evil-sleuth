use axum::{extract::State, response::Html};
use crate::AppState;

pub async fn index(State(state): State<AppState>) -> Html<String> {
    let ctx = tera::Context::new();
    let body = state.tera.render("_base.html", &ctx).unwrap_or_else(|e| {
        format!("<pre>template error: {e}</pre>")
    });
    Html(body)
}
