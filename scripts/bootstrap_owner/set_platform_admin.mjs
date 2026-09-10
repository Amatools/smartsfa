// Promove uma conta ja existente no Firebase Auth para platform_admin,
// criando/atualizando o documento usuarios/{uid} com os privilegios maximos.
//
// Uso:
//   1) Gere uma service account (Console Firebase > Configuracoes do projeto >
//      Contas de servico > Gerar nova chave privada) e salve o JSON nesta pasta
//      (nomes *service-account*.json / *firebase-adminsdk*.json ja estao no .gitignore).
//   2) set GOOGLE_APPLICATION_CREDENTIALS_JSON=caminho\para\chave.json
//   3) node set_platform_admin.mjs --email=contato@smartsfa.com.br
import { readFileSync } from 'node:fs';
import { initializeApp, cert } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

function required(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return value;
}

function arg(name) {
  const prefix = `--${name}=`;
  const found = process.argv.find((a) => a.startsWith(prefix));
  return found ? found.slice(prefix.length) : null;
}

async function run() {
  const serviceAccountPath = required('GOOGLE_APPLICATION_CREDENTIALS_JSON');
  const email = arg('email');
  if (!email) {
    throw new Error('Parametro obrigatorio: --email=<email>');
  }

  const serviceAccount = JSON.parse(readFileSync(serviceAccountPath, 'utf8'));
  initializeApp({ credential: cert(serviceAccount) });

  const auth = getAuth();
  const db = getFirestore();

  const user = await auth.getUserByEmail(email);

  await db.collection('usuarios').doc(user.uid).set(
    {
      uid: user.uid,
      email: user.email,
      displayName: user.displayName ?? email,
      platformRole: 'platform_admin',
      ativoGlobal: true,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  console.log(`OK: ${email} (uid=${user.uid}) agora e platform_admin.`);
}

run().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
