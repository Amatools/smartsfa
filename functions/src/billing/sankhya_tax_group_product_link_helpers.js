async function applyTaxGroupsToExistingProducts({
  firestore,
  tenantId,
  ncmToGroupId,
  normalizeDigits,
}) {
  const snapshot = await firestore
    .collection('produtos')
    .where('tenantId', '==', tenantId)
    .select('ncm', 'grupoTributarioId', 'deletedAt')
    .get();

  const writer = firestore.bulkWriter();
  writer.onWriteError((error) => error.failedAttempts < 3);
  let linkedCount = 0;

  try {
    for (const doc of snapshot.docs) {
      const data = doc.data() || {};
      if (data.deletedAt) {
        continue;
      }
      const ncmDigits = normalizeDigits(data.ncm);
      if (!ncmDigits) {
        continue;
      }
      const groupId = ncmToGroupId.get(ncmDigits);
      if (!groupId || data.grupoTributarioId === groupId) {
        continue;
      }
      writer.set(
        doc.ref,
        { grupoTributarioId: groupId },
        { merge: true },
      );
      linkedCount += 1;
    }
  } finally {
    await writer.close();
  }

  return linkedCount;
}

module.exports = {
  applyTaxGroupsToExistingProducts,
};
