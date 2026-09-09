/*
  Uso:
  1) Crie uma service account no Firebase e baixe o JSON.
  2) Defina GOOGLE_APPLICATION_CREDENTIALS apontando para esse JSON.
  3) Execute:
     node scripts/bootstrap_owner/create_owner.js \
       --projectId=SEU_PROJECT_ID \
       --email=owner@empresa.com \
       --password='SenhaForteAqui' \
       --nome='Owner Inicial'
*/

const admin = require('firebase-admin');

function arg(name) {
  const prefix = `--${name}=`;
  const found = process.argv.find((a) => a.startsWith(prefix));
  return found ? found.slice(prefix.length) : null;
}

async function main() {
  const projectId = arg('projectId');
  const email = arg('email');
  const password = arg('password');
  const nome = arg('nome') || 'Owner';

  if (!projectId || !email || !password) {
    throw new Error('Parametros obrigatorios: --projectId, --email, --password');
  }

  admin.initializeApp({ projectId });

  const auth = admin.auth();
  const db = admin.firestore();

  let userRecord;
  try {
    userRecord = await auth.getUserByEmail(email);
    console.log(`Usuario ja existe no Auth: ${userRecord.uid}`);
  } catch {
    userRecord = await auth.createUser({
      email,
      password,
      displayName: nome,
      emailVerified: true,
      disabled: false,
    });
    console.log(`Usuario criado no Auth: ${userRecord.uid}`);
  }

  await auth.setCustomUserClaims(userRecord.uid, {
    role: 'owner',
    ownerId: userRecord.uid,
  });

  const now = admin.firestore.FieldValue.serverTimestamp();

  await db.collection('usuarios').doc(userRecord.uid).set(
    {
      uid: userRecord.uid,
      role: 'owner',
      nome,
      email,
      ativo: true,
      ownerId: userRecord.uid,
      gerenteId: null,
      representanteId: null,
      createdAt: now,
      updatedAt: now,
    },
    { merge: true }
  );

  console.log('Owner bootstrap concluido com sucesso.');
  console.log(`UID: ${userRecord.uid}`);
}

main().catch((err) => {
  console.error('Falha no bootstrap do owner:', err.message);
  process.exit(1);
});
