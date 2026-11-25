//! Входы в сервисы на всех устройствах (SERVER_PROMPT этап 4, API.md «Сервисы»): ключи из keyring ↔
//! `GET/PUT /services/credentials`.
//!
//! Слияние трёхстороннее: в keyring (`sonar_cred_base`) лежит хэш того, что было на сервере после прошлого
//! обмена. По нему видно, кто поменялся: своё изменилось — едет на сервер, поменялся сервер — входим здесь,
//! на одной стороне пропало, а другая не менялась — отключаем и там. Первый обмен (базы нет) — своё побеждает,
//! остальное берём с сервера. Значения ключей в журнал не пишутся — только имена сервисов.

use crate::services::Core;
use crate::store::Store;
use serde_json::{Map, Value};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};
use std::sync::Mutex;

/// Поля одного сервиса — как на сервере (`server/sonar/api/services.py` `FIELDS`), без пустых.
pub type Fields = BTreeMap<String, String>;
/// Сервис → хэш полей, которые были на сервере после прошлого обмена.
type Base = BTreeMap<String, String>;

const BASE: &str = "sonar_cred_base";
/// Сервисы, которые знает сервер; остальные (VK, локальные файлы) не синкаются.
pub const SERVICES: [&str; 4] = ["soundcloud", "yandex", "youtube", "spotify"];

/// Не войти по пришедшему ключу (протух, сервис лежит) — второй раз тот же ключ до перезапуска не пробуем.
static FAILED: Mutex<BTreeSet<String>> = Mutex::new(BTreeSet::new());
/// Обмен после входа и фоновый не должны идти одновременно.
static RUNNING: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Step {
  /// Своё — на сервер.
  Push(String),
  /// Отключили здесь — убрать и с сервера.
  Delete(String),
  /// С сервера — войти здесь.
  Apply(String),
  /// Отключили на другом устройстве — отключить здесь.
  Forget(String),
}

pub fn hash(f: &Fields) -> String {
  let canon = serde_json::to_string(f).unwrap_or_default(); // BTreeMap — ключи уже по порядку
  Sha256::digest(canon.as_bytes()).iter().map(|b| format!("{b:02x}")).collect()
}

/// Что сделать по каждому сервису. Чистая функция — вся логика слияния здесь.
pub fn plan(local: &BTreeMap<String, Fields>, remote: &BTreeMap<String, Fields>, base: &Base) -> Vec<Step> {
  let services: BTreeSet<&String> = local.keys().chain(remote.keys()).collect();
  services
    .into_iter()
    .filter_map(|svc| {
      let was = base.get(svc);
      let s = svc.clone();
      match (local.get(svc).map(hash), remote.get(svc).map(hash)) {
        (Some(l), Some(r)) if l == r => None,
        (Some(l), Some(_)) if was == Some(&l) => Some(Step::Apply(s)),
        (Some(_), Some(_)) => Some(Step::Push(s)),
        (Some(l), None) if was == Some(&l) => Some(Step::Forget(s)),
        (Some(_), None) => Some(Step::Push(s)),
        (None, Some(r)) if was == Some(&r) => Some(Step::Delete(s)),
        (None, Some(_)) => Some(Step::Apply(s)),
        (None, None) => None,
      }
    })
    .collect()
}

fn service_of(step: &Step) -> &str {
  match step {
    Step::Push(s) | Step::Delete(s) | Step::Apply(s) | Step::Forget(s) => s,
  }
}

/// База после обмена: хэш того, что теперь лежит на сервере. `failed` — сервисы, где войти по ключу
/// с сервера не вышло (правило — в начале цикла ниже).
pub fn next_base(local: &BTreeMap<String, Fields>, remote: &BTreeMap<String, Fields>, old: &Base, steps: &[Step], failed: &BTreeSet<String>) -> Base {
  let services: BTreeSet<&String> = local.keys().chain(remote.keys()).collect();
  services
    .into_iter()
    .filter_map(|svc| {
      // не вошли по ключу с сервера (сейчас или пропущен как уже не прошедший):
      // свой есть — базы нет, следующий обмен зальёт свой рабочий вместо протухшего;
      // своего нет — база прежняя, иначе следующий обмен решит «у меня отключили» и удалит вход для всех
      if failed.contains(svc) {
        return if local.contains_key(svc) { None } else { old.get(svc).map(|h| (svc.clone(), h.clone())) };
      }
      let h = match steps.iter().find(|s| service_of(s) == svc) {
        None => remote.get(svc).map(hash), // совпадают
        Some(Step::Push(_)) => local.get(svc).map(hash),
        Some(Step::Apply(_)) => remote.get(svc).map(hash),
        Some(Step::Delete(_) | Step::Forget(_)) => None,
      };
      h.map(|h| (svc.clone(), h))
    })
    .collect()
}

/// Ответ `GET /services/credentials` → поля известных сервисов (лишнее и не строки — мимо).
pub fn parse_remote(v: &Value) -> BTreeMap<String, Fields> {
  let Some(obj) = v.as_object() else { return BTreeMap::new() };
  obj
    .iter()
    .filter(|(svc, _)| SERVICES.contains(&svc.as_str()))
    .filter_map(|(svc, f)| {
      let fields: Fields = f.as_object()?.iter().filter_map(|(k, v)| Some((k.clone(), v.as_str()?.to_owned()))).collect();
      Some((svc.clone(), fields))
    })
    .collect()
}

/// Тело `PUT /services/credentials`: своё с именем аккаунта, отключённое — `null`.
fn push_body(steps: &[Step], local: &BTreeMap<String, (Fields, Option<String>)>) -> Map<String, Value> {
  let mut body = Map::new();
  for step in steps {
    match step {
      Step::Push(svc) => {
        let Some((fields, name)) = local.get(svc) else { continue };
        let mut v: Map<String, Value> = fields.iter().map(|(k, v)| (k.clone(), Value::String(v.clone()))).collect();
        if let Some(n) = name {
          v.insert("name".into(), Value::String(n.clone()));
        }
        body.insert(svc.clone(), Value::Object(v));
      }
      Step::Delete(svc) => {
        body.insert(svc.clone(), Value::Null);
      }
      _ => {}
    }
  }
  body
}

/// Вышли из аккаунта или вошли в другой — прошлый обмен больше ни о чём не говорит.
pub fn reset() {
  let _ = crate::secrets::delete(BASE);
  FAILED.lock().unwrap().clear();
}

/// Пришедший ключ, по которому уже не вошли, не дёргаем каждые 2 минуты: такие Apply выкинуть,
/// сервисы — в `failed` (их база не сдвигается).
fn drop_tried(steps: &mut Vec<Step>, remote: &BTreeMap<String, Fields>, failed: &mut BTreeSet<String>) {
  let tried = FAILED.lock().unwrap().clone();
  steps.retain(|s| {
    let Step::Apply(svc) = s else { return true };
    let skip = remote.get(svc).is_some_and(|f| tried.contains(&format!("{svc}:{}", hash(f))));
    if skip {
      failed.insert(svc.clone());
    }
    !skip
  });
}

/// Войти и отключить здесь по шагам плана. → было ли что-то изменено.
async fn apply_here(core: &Core, steps: &[Step], remote: &BTreeMap<String, Fields>, failed: &mut BTreeSet<String>) -> bool {
  let mut changed = false;
  for step in steps {
    match step {
      Step::Apply(svc) => {
        let fields = &remote[svc];
        match core.apply_creds(svc, fields).await {
          Ok(()) => changed = true,
          Err(e) => {
            log::warn!("вход в {svc} с другого устройства не прошёл: {e}");
            FAILED.lock().unwrap().insert(format!("{svc}:{}", hash(fields)));
            failed.insert(svc.clone());
          }
        }
      }
      Step::Forget(svc) => match core.disconnect(svc).await {
        Ok(()) => changed = true,
        Err(e) => log::warn!("отключить {svc} по другому устройству не вышло: {e}"),
      },
      _ => {}
    }
  }
  changed
}

/// Один обмен. → true, если здесь что-то подключилось или отключилось (окну — `services-changed`).
pub async fn run(core: &Core, db: &Mutex<Store>) -> Result<bool, String> {
  let _guard = RUNNING.lock().await;
  let local_full = core.cred_snapshot().await;
  let local: BTreeMap<String, Fields> = local_full.iter().map(|(k, (f, _))| (k.clone(), f.clone())).collect();
  let remote = parse_remote(&crate::account::call(core, db, reqwest::Method::GET, "services/credentials", None, true).await?);
  let old: Base = crate::secrets::load(BASE).unwrap_or_default();
  let mut steps = plan(&local, &remote, &old);
  let mut failed = BTreeSet::new();
  drop_tried(&mut steps, &remote, &mut failed);

  let body = push_body(&steps, &local_full);
  if !body.is_empty() {
    crate::account::call(core, db, reqwest::Method::PUT, "services/credentials", Some(Value::Object(body)), true).await?;
  }
  let changed = apply_here(core, &steps, &remote, &mut failed).await;
  // за время обмена могли выйти из аккаунта — тогда базу не пишем (её уже стёр `reset`)
  if crate::sync::configured(db).is_some() {
    let _ = crate::secrets::save(BASE, &next_base(&local, &remote, &old, &steps, &failed));
  }
  Ok(changed)
}

#[cfg(test)]
mod tests {
  use super::*;

  fn f(pairs: &[(&str, &str)]) -> Fields {
    pairs.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect()
  }
  fn m(items: &[(&str, Fields)]) -> BTreeMap<String, Fields> {
    items.iter().map(|(k, v)| (k.to_string(), v.clone())).collect()
  }
  fn b(items: &[(&str, &Fields)]) -> Base {
    items.iter().map(|(k, v)| (k.to_string(), hash(v))).collect()
  }

  #[test]
  fn first_sync_pushes_local_and_takes_remote() {
    let steps = plan(&m(&[("yandex", f(&[("token", "y0_a")]))]), &m(&[("soundcloud", f(&[("client_id", "c")]))]), &Base::new());
    assert_eq!(steps, vec![Step::Apply("soundcloud".into()), Step::Push("yandex".into())]);
  }

  #[test]
  fn first_sync_conflict_local_wins() {
    let steps = plan(&m(&[("yandex", f(&[("token", "mine")]))]), &m(&[("yandex", f(&[("token", "theirs")]))]), &Base::new());
    assert_eq!(steps, vec![Step::Push("yandex".into())]);
  }

  #[test]
  fn equal_does_nothing() {
    let ym = f(&[("token", "y0_a")]);
    assert!(plan(&m(&[("yandex", ym.clone())]), &m(&[("yandex", ym)]), &Base::new()).is_empty());
  }

  #[test]
  fn changed_elsewhere_is_applied_changed_here_is_pushed() {
    let old = f(&[("token", "old")]);
    let new = f(&[("token", "new")]);
    let base = b(&[("yandex", &old)]);
    assert_eq!(plan(&m(&[("yandex", old.clone())]), &m(&[("yandex", new.clone())]), &base), vec![Step::Apply("yandex".into())]);
    assert_eq!(plan(&m(&[("yandex", new)]), &m(&[("yandex", old)]), &base), vec![Step::Push("yandex".into())]);
  }

  #[test]
  fn disconnect_travels_both_ways() {
    let ym = f(&[("token", "y0_a")]);
    let base = b(&[("yandex", &ym)]);
    assert_eq!(plan(&BTreeMap::new(), &m(&[("yandex", ym.clone())]), &base), vec![Step::Delete("yandex".into())]);
    assert_eq!(plan(&m(&[("yandex", ym)]), &BTreeMap::new(), &base), vec![Step::Forget("yandex".into())]);
  }

  #[test]
  fn disconnected_elsewhere_but_relogged_here_is_pushed() {
    let base = b(&[("yandex", &f(&[("token", "old")]))]);
    assert_eq!(plan(&m(&[("yandex", f(&[("token", "new")]))]), &BTreeMap::new(), &base), vec![Step::Push("yandex".into())]);
  }

  #[test]
  fn next_base_follows_the_server() {
    let a = f(&[("token", "a")]);
    let sc = f(&[("client_id", "x")]);
    let sp = f(&[("sp_dc", "s")]);
    let local = m(&[("yandex", a.clone()), ("spotify", sp.clone())]);
    let remote = m(&[("soundcloud", sc.clone()), ("youtube", f(&[("cookie", "new")]))]);
    let old = b(&[("spotify", &sp), ("youtube", &f(&[("cookie", "old")]))]);
    let steps = plan(&local, &remote, &old);
    let failed: BTreeSet<String> = ["youtube".to_string()].into();
    let next = next_base(&local, &remote, &old, &steps, &failed);
    assert_eq!(next.get("yandex"), Some(&hash(&a))); // Push
    assert_eq!(next.get("soundcloud"), Some(&hash(&sc))); // Apply
    assert_eq!(next.get("spotify"), None); // Forget
    assert_eq!(next.get("youtube"), old.get("youtube")); // Apply не прошёл — база прежняя
  }

  #[test]
  fn skipped_failed_apply_never_turns_into_delete() {
    // ключ с сервера уже не подошёл и пропущен (его нет в шагах) — база не должна стать хэшем сервера
    let sp = f(&[("sp_dc", "bad")]);
    let local = BTreeMap::new();
    let remote = m(&[("spotify", sp.clone())]);
    let mut steps = plan(&local, &remote, &Base::new());
    steps.clear();
    let failed: BTreeSet<String> = ["spotify".to_string()].into();
    let next = next_base(&local, &remote, &Base::new(), &steps, &failed);
    assert_eq!(next.get("spotify"), None);
    assert_eq!(plan(&local, &remote, &next), vec![Step::Apply("spotify".into())]);
  }

  #[test]
  fn failed_apply_with_own_key_pushes_own_next_time() {
    // с сервера пришёл протухший ключ, свой рабочий — следующий обмен заливает свой
    let mine = f(&[("client_id", "good")]);
    let bad = f(&[("client_id", "bad")]);
    let local = m(&[("soundcloud", mine.clone())]);
    let remote = m(&[("soundcloud", bad)]);
    let old = b(&[("soundcloud", &mine)]);
    let steps = plan(&local, &remote, &old);
    assert_eq!(steps, vec![Step::Apply("soundcloud".into())]);
    let failed: BTreeSet<String> = ["soundcloud".to_string()].into();
    let next = next_base(&local, &remote, &old, &steps, &failed);
    assert_eq!(plan(&local, &remote, &next), vec![Step::Push("soundcloud".into())]);
  }

  #[test]
  fn after_sync_the_next_plan_is_empty() {
    let local = m(&[("yandex", f(&[("token", "a")]))]);
    let remote = m(&[("soundcloud", f(&[("client_id", "x")]))]);
    let steps = plan(&local, &remote, &Base::new());
    let next = next_base(&local, &remote, &Base::new(), &steps, &BTreeSet::new());
    let both = m(&[("yandex", f(&[("token", "a")])), ("soundcloud", f(&[("client_id", "x")]))]);
    assert!(plan(&both, &both, &next).is_empty());
  }

  #[test]
  fn parse_remote_keeps_known_string_fields() {
    let v = serde_json::json!({"yandex": {"token": "t"}, "vk": {"token": "x"}, "soundcloud": {"client_id": "c", "n": 1}, "spotify": "bad"});
    let r = parse_remote(&v);
    assert_eq!(r.len(), 2);
    assert_eq!(r["soundcloud"], f(&[("client_id", "c")]));
  }

  #[test]
  fn push_body_has_name_and_nulls() {
    let local: BTreeMap<String, (Fields, Option<String>)> = [("yandex".to_string(), (f(&[("token", "t")]), Some("Folzy".to_string())))].into();
    let body = push_body(&[Step::Push("yandex".into()), Step::Delete("youtube".into()), Step::Apply("spotify".into())], &local);
    assert_eq!(Value::Object(body), serde_json::json!({"yandex": {"token": "t", "name": "Folzy"}, "youtube": null}));
  }
}
