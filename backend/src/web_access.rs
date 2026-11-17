//! Web access of the teachers, between the worlds, the database and the
//! mail: what a world reports is stored, mails go out, and the worlds
//! are told how a web access stands.

use anyhow::Result;
use lep_protocol::world::{Teachers, WebAccessRequest, JOB_WEB_ACCESS_STATUS};

use crate::app::AppState;
use crate::teachers::{self, Change, ConfirmError};
use crate::{clock, groups, jobs, mail};

/// Tells one world how the web access of an account stands.
async fn tell_world(app: &AppState, world_id: &str, account: &str) -> Result<()> {
    let status = teachers::status(&app.db, account).await?;
    jobs::add(
        &app.db,
        world_id,
        JOB_WEB_ACCESS_STATUS,
        &serde_json::to_value(status)?,
    )
    .await?;
    app.waiters.wake(world_id);
    Ok(())
}

/// Tells every world in which an account holds the privilege how its web
/// access stands.
async fn tell_worlds(app: &AppState, account: &str) -> Result<()> {
    for world_id in teachers::worlds_of(&app.db, account).await? {
        tell_world(app, &world_id, account).await?;
    }
    Ok(())
}

/// Stores who holds the privilege in a world, and tells the world how
/// the web access of each of them stands. A world reports its list at
/// every start, so its copy is fresh from then on.
pub async fn note_holders(app: &AppState, world_id: &str, list: &Teachers) -> Result<()> {
    teachers::set_holders(&app.db, world_id, &list.accounts).await?;
    groups::set_school_admins(&app.db, world_id, &list.school_admins).await?;
    for account in list
        .accounts
        .iter()
        .filter(|name| teachers::is_account(name))
    {
        tell_world(app, world_id, account).await?;
    }
    Ok(())
}

/// Does what a teacher asked for at the desk of a world. Returns false
/// if the request makes no sense.
pub async fn handle(app: &AppState, world_id: &str, request: &WebAccessRequest) -> Result<bool> {
    if !teachers::is_account(&request.account) {
        return Ok(false);
    }
    if !teachers::holds_in(&app.db, world_id, &request.account).await? {
        // The world did not report this account as a teacher. Nothing is
        // done, and the world may forget the event.
        tracing::warn!(
            account = %request.account,
            "web access asked for an account that does not hold the privilege"
        );
        return Ok(true);
    }
    let Some(change) = teachers::request(&app.db, request, clock::now()).await? else {
        return Ok(false);
    };
    if let Change::Mail { to, token } = &change {
        let minutes = teachers::TOKEN_SECONDS / 60;
        let mail = mail::confirmation(&app.public_url, to, &request.account, token, minutes);
        // If it fails, the teacher can ask for the mail again at the desk.
        app.mailer.send_later(mail, &request.account).await;
    }
    // Also when nothing changed: the desk shows what the backend knows.
    tell_worlds(app, &request.account).await?;
    Ok(true)
}

/// Confirms an address with the token from a mail and tells the worlds.
pub async fn confirm(app: &AppState, token: &str) -> Result<Result<String, ConfirmError>> {
    let outcome = teachers::confirm(&app.db, token, clock::now()).await?;
    if let Ok(account) = &outcome {
        tracing::info!(%account, "address confirmed");
        tell_worlds(app, account).await?;
    }
    Ok(outcome)
}
