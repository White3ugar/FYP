const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

const db = admin.firestore();

/**
 * Returns the three-letter abbreviation of a month based on its number.
 * @param {number} monthNum - The number of the month (1-12).
 * @return {string} The abbreviated month name.
 */
function getMonthAbbreviation(monthNum) {
  const months = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
  ];
  return months[monthNum - 1];
}

exports.repeatTransactions = functions.pubsub
    .schedule("every day 00:00")
    .timeZone("Asia/Kuala_Lumpur")
    .onRun(async () => {
      const today = new Date();
      const currentMonth = getMonthAbbreviation(today.getMonth() + 1);
      const day = String(today.getDate()).padStart(2, "0");
      const month = String(today.getMonth() + 1).padStart(2, "0");
      const year = today.getFullYear();
      const formattedDate = `${day}-${month}-${year}`;

      const usersSnapshot = await db.collection("expenses").get();

      for (const userDoc of usersSnapshot.docs) {
        const userId = userDoc.id;

        const recurringSnapshot = await db
            .collection("expenses")
            .doc(userId)
            .collection("Recurring")
            .get();

        for (const doc of recurringSnapshot.docs) {
          const data = doc.data();
          const repeatType = data.repeat;

          // Skip if repeat type is missing or 'None'
          if (!repeatType || repeatType === "None") continue;

          let shouldRepeat = false;

          const lastRepeated = data.lastRepeated || "";
          const lastRepeatedParts = lastRepeated.split("-");
          const year = lastRepeatedParts[2];
          const month = lastRepeatedParts[1];
          const day = lastRepeatedParts[0];

          const formattedLastDate = `${year}-${month}-${day}`;

          const lastRepeatedDate =
          lastRepeatedParts.length === 3 ?
                new Date(formattedLastDate) :
                null;

          if (repeatType === "Daily") {
            shouldRepeat = formattedDate !== lastRepeated;
          } else if (repeatType === "Weekly") {
            if (lastRepeatedDate) {
              const msInDay = 1000 * 60 * 60 * 24;
              const daysDiff = Math.floor((today - lastRepeatedDate) / msInDay);
              shouldRepeat = daysDiff >= 7;
            } else {
              shouldRepeat = true; // No lastRepeated means we should run it
            }
          } else if (repeatType === "Monthly") {
            if (lastRepeatedDate) {
              shouldRepeat = (
                today.getMonth() !== lastRepeatedDate.getMonth() ||
              today.getFullYear() !== lastRepeatedDate.getFullYear()
              );
            } else {
              shouldRepeat = true;
            }
          }

          if (!shouldRepeat) continue;

          // Add transaction for today
          await db
              .collection("expenses")
              .doc(userId)
              .collection("Months")
              .doc(currentMonth)
              .collection(formattedDate)
              .add({
                ...data,
                date: admin.firestore.Timestamp.fromDate(today),
              });

          // Update lastRepeated
          await doc.ref.update({lastRepeated: formattedDate});
        }
      }

      console.log("Repeat transactions processed successfully.");
      return null;
    });
